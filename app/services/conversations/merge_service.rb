# Merges source_conversation into target_conversation (same account, contact, inbox).
# Moves messages and related rows; deletes the source conversation.
class Conversations::MergeService
  pattr_initialize [:account!, :target_conversation!, :source_conversation!]

  def perform
    validate!
    merged_from_display_id = source_conversation.display_id

    ActiveRecord::Base.transaction do
      merge_labels
      move_messages
      reassign_mentions
      merge_conversation_participants
      reassign_csat_responses
      delete_notifications_for_source
      reassign_reporting_events
      destroy_source_ticket_link
      destroy_source_conversation!
      refresh_target!
    end

    dispatch_updated_event(merged_from_display_id)
    target_conversation.reload
  end

  private

  def validate!
    raise StandardError, 'Cannot merge a conversation with itself' if target_conversation.id == source_conversation.id

    unless target_conversation.account_id == source_conversation.account_id && target_conversation.account_id == account.id
      raise StandardError, 'Conversations must belong to the account'
    end

    unless target_conversation.contact_id == source_conversation.contact_id
      raise StandardError, 'Conversations must belong to the same contact'
    end

    return if target_conversation.inbox_id == source_conversation.inbox_id

    raise StandardError, 'Conversations must belong to the same inbox'
  end

  def merge_labels
    combined = (target_conversation.label_list + source_conversation.label_list).uniq
    return if combined == target_conversation.label_list

    target_conversation.update!(label_list: combined)
  end

  def move_messages
    Message.unscoped.where(conversation_id: source_conversation.id).update_all(
      conversation_id: target_conversation.id,
      inbox_id: target_conversation.inbox_id,
      updated_at: Time.current
    )
  end

  def reassign_mentions
    Mention.where(conversation_id: source_conversation.id).find_each do |mention|
      if Mention.exists?(conversation_id: target_conversation.id, user_id: mention.user_id)
        mention.destroy!
      else
        mention.update!(conversation_id: target_conversation.id)
      end
    end
  end

  def merge_conversation_participants
    ConversationParticipant.where(conversation_id: source_conversation.id).find_each do |participant|
      if ConversationParticipant.exists?(conversation_id: target_conversation.id, user_id: participant.user_id)
        participant.destroy!
      else
        participant.update!(conversation_id: target_conversation.id)
      end
    end
  end

  def reassign_csat_responses
    if target_conversation.csat_survey_response.present?
      CsatSurveyResponse.where(conversation_id: source_conversation.id).destroy_all
    else
      CsatSurveyResponse.where(conversation_id: source_conversation.id).update_all(conversation_id: target_conversation.id)
    end
  end

  def delete_notifications_for_source
    Notification.where(primary_actor_type: 'Conversation', primary_actor_id: source_conversation.id).delete_all
  end

  def reassign_reporting_events
    ReportingEvent.where(conversation_id: source_conversation.id).update_all(conversation_id: target_conversation.id)
  end

  def destroy_source_ticket_link
    return unless defined?(TicketConversation)

    TicketConversation.find_by(conversation_id: source_conversation.id)&.destroy!
  end

  def destroy_source_conversation!
    # Reload so associations reflect moved rows; avoid dependent: destroy on messages.
    source_conversation.reload
    source_conversation.destroy!
  end

  def refresh_target!
    target_conversation.reload
    msgs = target_conversation.messages.where(account_id: account.id)
    last_ts = [msgs.maximum(:created_at), target_conversation.last_activity_at].compact.max

    attrs = { last_activity_at: last_ts, updated_at: Time.current }
    first_reply = msgs.where.not(message_type: :activity).minimum(:created_at)
    attrs[:first_reply_created_at] = first_reply if target_conversation.first_reply_created_at.blank? && first_reply.present?

    target_conversation.update_columns(attrs)
  end

  def dispatch_updated_event(merged_from_display_id)
    target_conversation.dispatch_conversation_updated_event({ merged_from: merged_from_display_id })
  end
end
