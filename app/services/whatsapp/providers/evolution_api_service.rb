# Evolution API WhatsApp provider
# Docs: https://doc.evolution-api.com/v2/
# Webhook: user configures URL in Evolution (e.g. POST /webhooks/evolution)
class Whatsapp::Providers::EvolutionApiService < Whatsapp::Providers::BaseService
  def send_message(phone_number, message)
    @message = message
    if message.attachments.present?
      send_attachment_message(phone_number, message)
    elsif message.content_type == 'input_select'
      send_interactive_as_text(phone_number, message)
    else
      send_text_message(phone_number, message)
    end
  end

  def send_template(phone_number, template_info, message)
    # Evolution API does not use Meta templates; send template body as plain text fallback
    body_text = template_info[:parameters]&.dig(0, 'type') == 'body' ? template_body_text(template_info) : nil
    body_text ||= template_info[:name].to_s
    response = HTTParty.post(
      "#{api_base_path}/message/sendText/#{instance_name}",
      headers: api_headers,
      body: { number: normalize_number(phone_number), text: body_text }.to_json
    )
    process_response(response, message)
  end

  def sync_templates
    whatsapp_channel.mark_message_templates_updated
  end

  def validate_provider_config?
    response = HTTParty.get(
      "#{api_base_path}/instance/connectionState/#{instance_name}",
      headers: api_headers
    )
    return false unless response.success?

    state = response.parsed_response.dig('instance', 'state')
    state == 'open'
  end

  def api_headers
    { 'apikey' => whatsapp_channel.provider_config['api_key'], 'Content-Type' => 'application/json' }
  end

  def media_url(media_id)
    # Evolution may expose media via different endpoint; IncomingMessageEvolutionService handles download
    "#{api_base_path}/chat/getBase64FromMediaMessage/#{instance_name}"
  end

  def process_response(response, message)
    parsed = response.parsed_response
    if response.success? && parsed['key'].present?
      parsed.dig('key', 'id')
    else
      handle_error(response, message)
      nil
    end
  end

  def error_message(response)
    parsed = response.parsed_response
    parsed['message'] || parsed.dig('response', 'message')&.join(', ') || response.body
  end

  private

  def api_base_path
    base = whatsapp_channel.provider_config['api_base_url'].presence || ENV.fetch('EVOLUTION_API_BASE_URL', 'http://localhost:8080')
    base.to_s.sub(%r{/$}, '')
  end

  def instance_name
    whatsapp_channel.provider_config['evolution_instance'].to_s
  end

  def normalize_number(phone_number)
    phone_number.to_s.delete('+').strip
  end

  def send_text_message(phone_number, message)
    quoted = whatsapp_reply_context(message)
    body = { number: normalize_number(phone_number), text: message.outgoing_content }
    body[:quoted] = { key: { id: quoted[:message_id] }, message: { conversation: quoted[:text] } } if quoted.present?

    response = HTTParty.post(
      "#{api_base_path}/message/sendText/#{instance_name}",
      headers: api_headers,
      body: body.to_json
    )
    process_response(response, message)
  end

  def whatsapp_reply_context(message)
    reply_to = message.content_attributes&.dig(:in_reply_to_external_id)
    return nil if reply_to.blank?

    reply_message = Message.find_by(source_id: reply_to)
    return nil if reply_message.blank?

    { message_id: reply_to, text: reply_message.content.to_s }
  end

  def send_attachment_message(phone_number, message)
    attachment = message.attachments.first
    type_str = attachment.file_type.to_s
    type = %w[image audio video].include?(type_str) ? type_str : 'document'
    mimetype = evolution_mimetype(attachment, type)
    caption = %w[audio sticker].include?(type) ? '' : (message.outgoing_content.presence || '')
    filename = attachment.file.respond_to?(:filename) ? attachment.file.filename.presence : nil
    filename ||= "file.#{type}"

    body = {
      number: normalize_number(phone_number),
      mediatype: type,
      mimetype: mimetype,
      caption: caption,
      media: attachment.download_url,
      fileName: filename.to_s
    }

    response = HTTParty.post(
      "#{api_base_path}/message/sendMedia/#{instance_name}",
      headers: api_headers,
      body: body.to_json
    )
    process_response(response, message)
  end

  def send_interactive_as_text(phone_number, message)
    # Evolution API has different interactive API; send as text for MVP
    text = message.outgoing_content.presence || message.content_attributes['items']&.map { |i| i['title'] }&.join(', ')
    response = HTTParty.post(
      "#{api_base_path}/message/sendText/#{instance_name}",
      headers: api_headers,
      body: { number: normalize_number(phone_number), text: text.to_s }.to_json
    )
    process_response(response, message)
  end

  def template_body_text(template_info)
    comps = template_info[:parameters] || []
    body_comp = comps.find { |c| c['type'] == 'body' }
    return nil if body_comp.blank?

    body_comp['parameters']&.map { |p| p['text'] }&.join(' ')
  end

  def evolution_mimetype(attachment, type)
    return 'application/octet-stream' if attachment.file_type == :file || type == 'document'

    if attachment.file.respond_to?(:content_type) && attachment.file.content_type.present?
      return attachment.file.content_type
    end

    { 'image' => 'image/jpeg', 'audio' => 'audio/ogg', 'video' => 'video/mp4' }[type] || 'application/octet-stream'
  end
end
