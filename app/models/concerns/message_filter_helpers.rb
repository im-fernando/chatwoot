module MessageFilterHelpers
  extend ActiveSupport::Concern

  def reportable?
    incoming? || outgoing?
  end

  def webhook_sendable?
    incoming? || outgoing? || template?
  end

  def slack_hook_sendable?
    incoming? || outgoing? || template?
  end

  def notifiable?
    return false if respond_to?(:hidden_from_agent_timeline?) && hidden_from_agent_timeline?

    (incoming? || outgoing?) && !private?
  end

  def conversation_transcriptable?
    incoming? || outgoing?
  end

  def email_reply_summarizable?
    incoming? || outgoing? || input_csat?
  end

  def instagram_story_mention?
    inbox.instagram? && try(:content_attributes)[:image_type] == 'story_mention'
  end
end
