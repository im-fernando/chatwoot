class CsatSurveyListener < BaseListener
  def conversation_status_changed(event)
    conversation = extract_conversation_and_account(event)[0]

    return unless conversation.resolved?

    CsatSurveyService.new(conversation: conversation).perform
  end

  def message_created(event)
    message = extract_message_and_account(event)[0]
    CsatSurveys::TextFlowProcessor.new(message: message).perform
  end

  def message_updated(event)
    message = extract_message_and_account(event)[0]
    return unless message.input_csat?

    CsatSurveys::ResponseBuilder.new(message: message).perform
  end
end
