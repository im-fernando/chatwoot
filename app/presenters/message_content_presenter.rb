class MessageContentPresenter < SimpleDelegator
  def outgoing_content
    Messages::MarkdownRendererService.new(
      content_with_survey_link,
      conversation.inbox.channel_type,
      conversation.inbox.channel
    ).render
  end

  def webhook_content
    content_with_survey_link
  end

  private

  def content_with_survey_link
    if should_append_survey_link?
      survey_link = survey_url(conversation.uuid)
      custom_message = inbox.csat_config&.dig('message')
      custom_message.present? ? "#{custom_message} #{survey_link}" : I18n.t('conversations.survey.response', link: survey_link)
    else
      content
    end
  end

  def should_append_survey_link?
    return false unless input_csat? && !inbox.web_widget?

    # For non-official WhatsApp providers (Baileys/Evolution API), CSAT can be
    # collected via text replies (1-5). In that mode we shouldn't append the
    # survey link.
    if inbox.channel_type == 'Channel::Whatsapp' &&
       inbox.channel.try(:provider) == 'evolution_api' &&
       inbox.csat_config&.dig('text_flow_enabled')
      return false
    end

    true
  end

  def survey_url(conversation_uuid)
    "#{ENV.fetch('FRONTEND_URL', nil)}/survey/responses/#{conversation_uuid}"
  end
end
