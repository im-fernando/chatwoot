class MessageFinder
  def initialize(conversation, params)
    @conversation = conversation
    @params = params
  end

  def perform
    filter_hidden_messages(current_messages)
  end

  private

  def conversation_messages
    @conversation.messages.includes(:attachments, :sender, sender: { avatar_attachment: [:blob] })
  end

  def messages
    scoped = conversation_messages

    # Always hide CSAT text-flow prompts (sent to customer) from agent timeline.
    # These are internal flow-control messages and shouldn't be visible in the conversation panel.
    scoped = scoped.where(
      "NOT (COALESCE(content_attributes::jsonb, '{}'::jsonb) ? 'csat_text_flow_prompt')"
    )

    # Hide the CSAT prompt message itself for Evolution text-flow CSAT.
    scoped = scoped.where.not(content_type: :input_csat) if hide_csat_text_flow_messages?

    return scoped if @params[:filter_internal_messages].blank?

    scoped.where.not('private = ? OR message_type = ?', true, 2)
  end

  def current_messages
    if @params[:after].present? && @params[:before].present?
      messages_between(@params[:after].to_i, @params[:before].to_i)
    elsif @params[:before].present?
      messages_before(@params[:before].to_i)
    elsif @params[:after].present?
      messages_after(@params[:after].to_i)
    else
      messages_latest
    end
  end

  def filter_hidden_messages(result)
    Array(result).reject(&:hidden_from_agent_timeline?)
  end

  def messages_after(after_id)
    messages.reorder('created_at asc').where('id > ?', after_id).limit(100)
  end

  def messages_before(before_id)
    messages.reorder('created_at desc').where('id < ?', before_id).limit(20).reverse
  end

  def messages_between(after_id, before_id)
    messages.reorder('created_at asc').where('id >= ? AND id < ?', after_id, before_id).limit(1000)
  end

  def messages_latest
    messages.reorder('created_at desc').limit(20).reverse
  end

  def hide_csat_text_flow_messages?
    inbox = @conversation&.inbox
    return false if inbox.blank?
    return false unless inbox.channel_type == 'Channel::Whatsapp'
    return false unless inbox.channel.try(:provider) == 'evolution_api'

    inbox.csat_config&.dig('text_flow_enabled') == true
  end
end
