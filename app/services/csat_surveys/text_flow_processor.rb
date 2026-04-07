class CsatSurveys::TextFlowProcessor
  pattr_initialize [:message!]

  YES_VALUES = %w[sim s yes y].freeze
  NO_VALUES = %w[nao não n no].freeze

  def perform
    return unless eligible?

    flow = conversation.additional_attributes.is_a?(Hash) ? conversation.additional_attributes['csat_text_flow'] : nil
    return unless flow.is_a?(Hash)

    state = flow['state']
    csat_message = csat_message_from(flow['csat_message_id'])

    case state
    when 'await_rating'
      handle_rating(csat_message)
    when 'await_feedback_optin'
      handle_feedback_optin
    when 'await_feedback_text'
      handle_feedback_text(csat_message)
    else
      clear_flow!
    end

    # The customer replies (rating/opt-in/feedback) should not be visible to agents.
    # We process the value, then remove the incoming message from the conversation timeline.
    destroy_customer_reply_message!
  end

  private

  def eligible?
    return false unless message.incoming?
    return false if message.private?
    return false unless message.sender.is_a?(Contact)

    inbox.channel_type == 'Channel::Whatsapp' &&
      inbox.channel.try(:provider) == 'evolution_api' &&
      inbox.csat_config&.dig('text_flow_enabled') == true
  end

  def conversation
    message.conversation
  end

  def inbox
    message.inbox
  end

  def normalized_body
    message.content.to_s.strip.downcase
  end

  def csat_message_from(id)
    return nil if id.blank?

    Message.find_by(id: id, conversation_id: conversation.id, content_type: :input_csat)
  end

  def handle_rating(csat_message)
    rating = normalized_body.match?(/\A[1-5]\z/) ? normalized_body.to_i : nil

    if rating.blank?
      csat_message&.destroy!
      clear_flow!
      destroy_customer_reply_message!
      return
    end

    return clear_flow! if csat_message.blank?

    update_csat_message_submitted_values!(csat_message, rating: rating)
    update_flow!(state: 'await_feedback_optin', csat_message_id: csat_message.id)
    send_outgoing_text(I18n.t('conversations.templates.csat_text_flow.feedback_optin', default: 'Quer deixar um feedback? Responda SIM ou NÃO.'))
  end

  def handle_feedback_optin
    body = normalized_body
    if YES_VALUES.include?(body)
      update_flow!(state: 'await_feedback_text')
      send_outgoing_text(I18n.t('conversations.templates.csat_text_flow.feedback_prompt', default: 'Por favor, escreva seu feedback.'))
    elsif NO_VALUES.include?(body)
      clear_flow!
      send_outgoing_text(I18n.t('conversations.templates.csat_text_flow.thanks', default: 'Obrigado pela sua avaliação!'))
    else
      clear_flow!
    end
  end

  def handle_feedback_text(csat_message)
    return clear_flow! if csat_message.blank?

    feedback = message.content.to_s.strip
    update_csat_message_submitted_values!(csat_message, feedback_message: feedback)
    clear_flow!
    send_outgoing_text(I18n.t('conversations.templates.csat_text_flow.thanks', default: 'Obrigado pela sua avaliação!'))
  end

  def destroy_customer_reply_message!
    return if message.blank?
    return unless message.persisted?

    message.destroy!
  rescue StandardError => e
    Rails.logger.warn("CsatSurveys::TextFlowProcessor: failed to destroy csat reply message #{message&.id}: #{e.message}")
  end

  def update_csat_message_submitted_values!(csat_message, rating: nil, feedback_message: nil)
    attrs = csat_message.content_attributes.is_a?(Hash) ? csat_message.content_attributes : {}
    attrs['submitted_values'] ||= {}
    attrs['submitted_values']['csat_survey_response'] ||= {}
    attrs['submitted_values']['csat_survey_response']['rating'] = rating if rating.present?
    attrs['submitted_values']['csat_survey_response']['feedback_message'] = feedback_message if feedback_message.present?

    csat_message.update!(content_attributes: attrs)
  end

  def send_outgoing_text(content)
    conversation.messages.create!(
      account: conversation.account,
      inbox: inbox,
      message_type: :outgoing,
      content_type: :text,
      content: content.to_s,
      content_attributes: {
        csat_text_flow_prompt: true
      }
    )
  end

  def update_flow!(state:, csat_message_id: nil)
    attrs = conversation.additional_attributes.is_a?(Hash) ? conversation.additional_attributes : {}
    current = attrs['csat_text_flow'].is_a?(Hash) ? attrs['csat_text_flow'] : {}
    current['state'] = state
    current['csat_message_id'] = csat_message_id if csat_message_id.present?
    current['updated_at'] = Time.current.iso8601
    attrs['csat_text_flow'] = current
    conversation.update!(additional_attributes: attrs)
  end

  def clear_flow!
    attrs = conversation.additional_attributes.is_a?(Hash) ? conversation.additional_attributes : {}
    attrs.delete('csat_text_flow')
    conversation.update!(additional_attributes: attrs)
  end
end

