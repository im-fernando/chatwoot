class CsatSurveyService
  pattr_initialize [:conversation!]

  def perform
    return unless should_send_csat_survey?

    if evolution_provider? && text_flow_enabled?
      send_whatsapp_text_flow_survey
      return
    end

    if whatsapp_channel? && !evolution_provider? && template_available_and_approved?
      send_whatsapp_template_survey
    elsif inbox.twilio_whatsapp? && twilio_template_available_and_approved?
      send_twilio_whatsapp_template_survey
    elsif within_messaging_window?
      ::MessageTemplates::Template::CsatSurvey.new(conversation: conversation).perform
    else
      create_csat_not_sent_activity_message
    end
  end

  private

  delegate :inbox, :contact, to: :conversation

  def should_send_csat_survey?
    conversation_allows_csat? && csat_enabled? && !csat_already_sent? && csat_allowed_by_survey_rules?
  end

  def conversation_allows_csat?
    conversation.resolved? && !conversation.tweet?
  end

  def csat_enabled?
    inbox.csat_survey_enabled?
  end

  def csat_already_sent?
    conversation.messages.where(content_type: :input_csat).present?
  end

  def within_messaging_window?
    # Evolution/Baileys doesn't have the Meta 24h session restriction, so we
    # allow sending CSAT outside the normal reply window.
    return true if evolution_provider?

    conversation.can_reply?
  end

  def csat_allowed_by_survey_rules?
    return true unless survey_rules_configured?

    labels = conversation.label_list
    return true if rule_values.empty?

    case rule_operator
    when 'contains'
      rule_values.any? { |label| labels.include?(label) }
    when 'does_not_contain'
      rule_values.none? { |label| labels.include?(label) }
    else
      true
    end
  end

  def survey_rules_configured?
    return false if csat_config.blank?
    return false if csat_config['survey_rules'].blank?

    rule_values.any?
  end

  def rule_operator
    csat_config.dig('survey_rules', 'operator') || 'contains'
  end

  def rule_values
    csat_config.dig('survey_rules', 'values') || []
  end

  def whatsapp_channel?
    inbox.channel_type == 'Channel::Whatsapp'
  end

  def evolution_provider?
    inbox.channel.try(:provider) == 'evolution_api'
  end

  def template_available_and_approved?
    template_config = inbox.csat_config&.dig('template')
    return false unless template_config

    template_name = template_config['name'] || CsatTemplateNameService.csat_template_name(inbox.id)

    status_result = inbox.channel.provider_service.get_template_status(template_name)

    status_result[:success] && status_result[:template][:status] == 'APPROVED'
  rescue StandardError => e
    Rails.logger.error "Error checking CSAT template status: #{e.message}"
    false
  end

  def twilio_template_available_and_approved?
    template_config = inbox.csat_config&.dig('template')
    return false unless template_config

    content_sid = template_config['content_sid']
    return false unless content_sid

    template_service = Twilio::CsatTemplateService.new(inbox.channel)
    status_result = template_service.get_template_status(content_sid)

    status_result[:success] && status_result[:template][:status] == 'approved'
  rescue StandardError => e
    Rails.logger.error "Error checking Twilio CSAT template status: #{e.message}"
    false
  end

  def send_whatsapp_template_survey
    template_config = inbox.csat_config&.dig('template')
    template_name = template_config['name'] || CsatTemplateNameService.csat_template_name(inbox.id)

    phone_number = conversation.contact_inbox.source_id
    template_info = build_template_info(template_name, template_config)
    message = build_csat_message

    message_id = inbox.channel.provider_service.send_template(phone_number, template_info, message)

    message.update!(source_id: message_id) if message_id.present?
  rescue StandardError => e
    Rails.logger.error "Error sending WhatsApp CSAT template for conversation #{conversation.id}: #{e.message}"
  end

  def build_template_info(template_name, template_config)
    {
      name: template_name,
      lang_code: template_config['language'] || 'en',
      parameters: [
        {
          type: 'button',
          sub_type: 'url',
          index: '0',
          parameters: [{ type: 'text', text: conversation.uuid }]
        }
      ]
    }
  end

  def build_csat_message
    conversation.messages.build(
      account: conversation.account,
      inbox: inbox,
      message_type: :outgoing,
      content: csat_message_content,
      content_type: :input_csat
    )
  end

  def csat_message_content
    base = inbox.csat_config&.dig('message') || 'Please rate this conversation'
    return base unless evolution_provider? && text_flow_enabled?

    options = [
      "1 😞 Péssimo",
      "2 😑 Regular",
      "3 😐 Ok",
      "4 😀 Bom",
      "5 😍 Excelente"
    ].join("\n")

    "#{base}\n\nResponda com um número de 1 a 5:\n#{options}"
  end

  def send_whatsapp_text_flow_survey
    message = build_csat_message
    message.save!

    set_text_flow_state!(csat_message_id: message.id, state: 'await_rating')
  rescue StandardError => e
    Rails.logger.error "Error sending WhatsApp CSAT text flow for conversation #{conversation.id}: #{e.message}"
  end

  def set_text_flow_state!(csat_message_id:, state:)
    attrs = conversation.additional_attributes.is_a?(Hash) ? conversation.additional_attributes : {}
    attrs['csat_text_flow'] = { 'state' => state, 'csat_message_id' => csat_message_id, 'created_at' => Time.current.iso8601 }
    conversation.update!(additional_attributes: attrs)
  end

  def text_flow_enabled?
    csat_config['text_flow_enabled'] == true
  end

  def csat_config
    inbox.csat_config || {}
  end

  def send_twilio_whatsapp_template_survey
    template_config = inbox.csat_config&.dig('template')
    content_sid = template_config['content_sid']

    phone_number = conversation.contact_inbox.source_id
    content_variables = { '1' => conversation.uuid }
    message = build_csat_message

    send_service = Twilio::SendOnTwilioService.new(message: message)
    result = send_service.send_csat_template_message(
      phone_number: phone_number,
      content_sid: content_sid,
      content_variables: content_variables
    )

    message.update!(source_id: result[:message_id]) if result[:success] && result[:message_id].present?
  rescue StandardError => e
    Rails.logger.error "Error sending Twilio WhatsApp CSAT template for conversation #{conversation.id}: #{e.message}"
  end

  def create_csat_not_sent_activity_message
    content = I18n.t('conversations.activity.csat.not_sent_due_to_messaging_window')
    activity_message_params = {
      account_id: conversation.account_id,
      inbox_id: conversation.inbox_id,
      message_type: :activity,
      content: content
    }
    ::Conversations::ActivityMessageJob.perform_later(conversation, activity_message_params) if content
  end
end
