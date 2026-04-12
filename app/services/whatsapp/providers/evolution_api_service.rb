# Evolution API WhatsApp provider
# Docs: https://doc.evolution-api.com/v2/
# Webhook: user configures URL in Evolution (e.g. POST /webhooks/evolution)
class Whatsapp::Providers::EvolutionApiService < Whatsapp::Providers::BaseService
  def send_message(phone_number, message)
    @message = message
    if message.attachments.present?
      if message.attachments.all?(&:contact?)
        send_contact_message(phone_number, message)
      else
        send_attachment_message(phone_number, message)
      end
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
      "#{api_base_path}/message/sendText/#{escaped_instance_name}",
      headers: api_headers,
      body: { number: normalize_number(phone_number), text: body_text }.to_json
    )
    process_response(response, message)
  end

  def sync_templates
    whatsapp_channel.mark_message_templates_updated
  end

  def validate_provider_config?
    return true if whatsapp_channel.provider_config['skip_connection_validation'] == true

    response = HTTParty.get(
      "#{api_base_path}/instance/connectionState/#{escaped_instance_name}",
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
    "#{api_base_path}/chat/getBase64FromMediaMessage/#{escaped_instance_name}"
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
    if parsed.is_a?(Hash)
      parsed['message'] || (parsed.dig('response', 'message').is_a?(Array) ? parsed.dig('response', 'message').join(', ') : parsed.dig('response', 'message')) || response.body
    else
      response.body.to_s.truncate(500) # Evita salvar todo o HTML no banco de dados.
    end
  end

  private

  def api_base_path
    base = whatsapp_channel.provider_config['api_base_url'].presence || ENV.fetch('EVOLUTION_API_BASE_URL', 'http://localhost:8080')
    base.to_s.sub(%r{/$}, '')
  end

  def instance_name
    whatsapp_channel.provider_config['evolution_instance'].to_s
  end

  def escaped_instance_name
    CGI.escape(instance_name)
  end

  def normalize_number(phone_number)
    phone_number.to_s.delete('+').strip
  end

  def send_text_message(phone_number, message)
    quoted = whatsapp_reply_context(phone_number, message)
    text = Whatsapp::OutgoingSignature.body_for_whatsapp(message).to_s.gsub(/\n+\z/, '')
    body = { number: normalize_number(phone_number), text: text }
    body[:quoted] = evolution_quoted_payload(quoted) if quoted.present?

    response = HTTParty.post(
      "#{api_base_path}/message/sendText/#{escaped_instance_name}",
      headers: api_headers,
      body: body.to_json
    )
    process_response(response, message)
  end

  def whatsapp_reply_context(phone_number, message)
    reply_to = message.content_attributes&.dig(:in_reply_to_external_id) || message.content_attributes&.dig('in_reply_to_external_id')
    return nil if reply_to.blank?

    # Limit lookup to the same conversation to avoid cross-thread mismatches.
    reply_message = message.conversation&.messages&.find_by(source_id: reply_to) || Message.find_by(source_id: reply_to)
    return nil if reply_message.blank?

    {
      message_id: reply_to,
      remote_jid: evolution_remote_jid_for(phone_number),
      from_me: reply_message.outgoing?,
      text: reply_message.content.to_s
    }
  end

  def evolution_remote_jid_for(phone_number)
    raw = phone_number.to_s.strip
    return raw if raw.include?('@')

    "#{normalize_number(raw)}@s.whatsapp.net"
  end

  # Evolution API expects quoted message metadata; providing remoteJid/fromMe improves quote rendering in WhatsApp clients.
  def evolution_quoted_payload(quoted)
    key = {
      id: quoted[:message_id],
      remoteJid: quoted[:remote_jid],
      fromMe: quoted[:from_me]
    }.compact

    {
      key: key,
      message: { conversation: quoted[:text].to_s }
    }
  end

  def send_attachment_message(phone_number, message)
    last_response_id = nil
    message.attachments.each_with_index do |attachment, index|
      last_response_id = send_single_attachment(phone_number, message, attachment, caption_for_index: index)
    end
    last_response_id
  end

  def send_single_attachment(phone_number, message, attachment, caption_for_index: 0)
    type_str = attachment.file_type.to_s
    type = %w[image audio video].include?(type_str) ? type_str : 'document'
    mimetype = evolution_mimetype(attachment, type)
    # Only the first attachment gets a caption
    caption =
      if caption_for_index.positive? || type == 'audio' || attachment.file_type.to_s == 'sticker'
        ''
      else
        Whatsapp::OutgoingSignature.body_for_whatsapp(message).to_s.gsub(/\n+\z/, '').presence || ''
      end
    filename = attachment.file.respond_to?(:filename) ? attachment.file.filename.presence : nil
    filename ||= "file.#{type}"

    media_data, mimetype, filename = evolution_audio_media_bundle(attachment, mimetype, filename) if type == 'audio'
    media_data ||= attachment_media_for_evolution(attachment, mimetype)
    return handle_error_with_message(message, 'Could not read attachment file') if media_data.blank?

    return send_evolution_audio(phone_number, message, media_data, mimetype, filename) if type == 'audio'

    body = {
      number: normalize_number(phone_number),
      mediatype: type,
      mimetype: mimetype,
      caption: caption,
      media: media_data,
      fileName: filename.to_s
    }

    response = HTTParty.post(
      "#{api_base_path}/message/sendMedia/#{escaped_instance_name}",
      headers: api_headers,
      body: body.to_json
    )
    process_response(response, message)
  end

  # sendWhatsAppAudio: formatos comuns ok (ogg, mp3, m4a); WAV/WebM do web → transcode M4A + ptt: true.
  # Web dashboard often records WAV or WebM — Evolution rejects those on this endpoint.
  def send_evolution_audio(phone_number, message, audio_data, mimetype, filename)
    number = normalize_number(phone_number)
    quoted = whatsapp_reply_context(phone_number, message)
    quoted_payload = quoted.present? ? evolution_quoted_payload(quoted) : nil

    if evolution_audio_ptt_friendly?(mimetype, filename)
      # Evolution/WhatsApp trata melhor áudio de voz como PTT; doc de exemplo retorna audio/mp4 + ptt: true.
      body = { number: number, audio: audio_data, ptt: true }
      body[:quoted] = quoted_payload if quoted_payload.present?
      response = HTTParty.post(
        "#{api_base_path}/message/sendWhatsAppAudio/#{escaped_instance_name}",
        headers: api_headers,
        body: body.to_json
      )
      parsed = response.parsed_response
      if response.success? && parsed.is_a?(Hash) && parsed['key'].present?
        return process_response(response, message)
      end

      Rails.logger.warn(
        "[Evolution] sendWhatsAppAudio failed (status=#{response.code}); trying sendMedia. Body: #{response.body.to_s.truncate(400)}"
      )
    end

    send_evolution_audio_as_media(phone_number, message, audio_data, mimetype, filename)
  end

  def send_evolution_audio_as_media(phone_number, message, audio_data, mimetype, filename)
    body = {
      number: normalize_number(phone_number),
      mediatype: 'audio',
      mimetype: mimetype,
      caption: '',
      media: audio_data,
      fileName: filename.to_s
    }

    response = HTTParty.post(
      "#{api_base_path}/message/sendMedia/#{escaped_instance_name}",
      headers: api_headers,
      body: body.to_json
    )
    process_response(response, message)
  end

  def evolution_audio_ptt_friendly?(mimetype, filename)
    hint = "#{mimetype} #{filename}".downcase
    hint.match?(/\.(ogg|opus|mp3|m4a)\b/) ||
      mimetype.to_s.match?(%r{\Aaudio/(ogg|mpeg|mp3|mp4|x-m4a)\b}i)
  end

  def attachment_media_for_evolution(attachment, mimetype)
    return nil unless attachment.file.attached?

    content = attachment.file.download
    Base64.strict_encode64(content)
  end

  def handle_error_with_message(message, msg)
    message.update!(status: :failed, external_error: msg)
    nil
  end

  def send_interactive_as_text(phone_number, message)
    # Evolution API has different interactive API; send as text for MVP
    text = Whatsapp::OutgoingSignature.body_for_whatsapp_interactive(message).to_s.gsub(/\n+\z/, '')
    response = HTTParty.post(
      "#{api_base_path}/message/sendText/#{escaped_instance_name}",
      headers: api_headers,
      body: { number: normalize_number(phone_number), text: text.to_s }.to_json
    )
    process_response(response, message)
  end

  # https://doc.evolution-api.com/v2/api-reference/message-controller/send-contact
  def send_contact_message(phone_number, message)
    contacts_payload = message.attachments.select(&:contact?).filter_map { |att| evolution_contact_entry(att) }
    return handle_error_with_message(message, 'No valid contact phone for Evolution sendContact') if contacts_payload.empty?

    caption = post_evolution_contact_caption(phone_number, message)
    return nil if caption == :failed

    body = {
      number: normalize_number(phone_number),
      contact: contacts_payload
    }
    response = HTTParty.post(
      "#{api_base_path}/message/sendContact/#{escaped_instance_name}",
      headers: api_headers,
      body: body.to_json
    )
    process_response(response, message)
  end

  def evolution_contact_entry(attachment)
    meta = (attachment.meta || {}).with_indifferent_access
    phone_raw = attachment.fallback_title.to_s.strip
    wuid = normalize_number(phone_raw)
    return nil if wuid.blank?

    first = meta[:first_name].presence || meta[:firstName]
    last = meta[:last_name].presence || meta[:lastName]
    full_name = [first, last].compact.join(' ').presence || phone_raw.presence || 'Contact'

    {
      fullName: full_name,
      wuid: wuid,
      phoneNumber: evolution_formatted_phone(phone_raw, wuid),
      organization: meta[:organization].to_s,
      email: meta[:email].to_s,
      url: meta[:url].to_s
    }
  end

  def evolution_formatted_phone(display, wuid)
    s = display.to_s.strip
    return "+#{wuid}" if s.blank?

    s
  end

  # Optional user text before vCard; no agent signature (unlike post_evolution_signed_text_preamble).
  def post_evolution_contact_caption(phone_number, message)
    text = Whatsapp::OutgoingSignature.trim_body(message.outgoing_content).to_s.gsub(/\n+\z/, '')
    return :skipped if text.blank?

    quoted = whatsapp_reply_context(phone_number, message)
    body = { number: normalize_number(phone_number), text: text }
    body[:quoted] = evolution_quoted_payload(quoted) if quoted.present?

    response = HTTParty.post(
      "#{api_base_path}/message/sendText/#{escaped_instance_name}",
      headers: api_headers,
      body: body.to_json
    )
    parsed = response.parsed_response
    if response.success? && parsed.is_a?(Hash) && parsed['key'].present?
      :sent
    else
      handle_error(response, message)
      :failed
    end
  end

  # Sends "> Name" / "> Name\n…" before audio or sticker; does not set message.source_id on success.
  def post_evolution_signed_text_preamble(phone_number, message)
    text = Whatsapp::OutgoingSignature.body_for_whatsapp(message).to_s.gsub(/\n+\z/, '')
    return :skipped if text.blank?

    quoted = whatsapp_reply_context(phone_number, message)
    body = { number: normalize_number(phone_number), text: text }
    body[:quoted] = evolution_quoted_payload(quoted) if quoted.present?

    response = HTTParty.post(
      "#{api_base_path}/message/sendText/#{escaped_instance_name}",
      headers: api_headers,
      body: body.to_json
    )
    parsed = response.parsed_response
    if response.success? && parsed.is_a?(Hash) && parsed['key'].present?
      :sent
    else
      handle_error(response, message)
      :failed
    end
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

  def evolution_audio_media_bundle(attachment, mimetype, filename)
    return [nil, mimetype, filename] unless attachment.file.attached?

    raw_mime = mimetype.to_s
    raw_name = filename.to_s
    return [nil, mimetype, filename] if evolution_audio_ptt_friendly?(raw_mime, raw_name)

    # Evolution costuma rejeitar WAV/WebM do dashboard. Preferimos M4A (audio/mp4 + PTT na API).
    converted, out_mime, out_name = transcode_audio_for_evolution(attachment, mimetype: mimetype)
    return [nil, mimetype, filename] if converted.blank?

    [converted, out_mime, out_name]
  end

  def transcode_audio_for_evolution(attachment, mimetype:)
    content = attachment.file.download
    return [nil, nil, nil] if content.blank?

    require 'tempfile'
    require 'open3'

    mimetype_lc = mimetype.to_s.downcase
    ext_from_mime =
      case mimetype_lc
      when 'audio/wave' then '.wav'
      when 'audio/x-aac', 'audio/aac' then '.aac'
      when 'audio/ogg', 'audio/opus' then '.ogg'
      when 'audio/mpeg', 'audio/mp3' then '.mp3'
      when 'audio/mp4', 'audio/x-m4a' then '.m4a'
      when 'audio/webm', 'audio/x-webm' then '.webm'
      else nil
      end

    input_ext = File.extname(attachment.file.filename.to_s).presence || ext_from_mime
    input_ext = '.bin' if input_ext.blank?
    input = Tempfile.new(['chatwoot_audio_in', input_ext])
    input.binmode
    input.write(content)
    input.rewind

    # 1) M4A/AAC — alinhado à resposta da doc Evolution (audio/mp4, ptt).
    m4a = Tempfile.new(['chatwoot_audio_out', '.m4a'])
    m4a.binmode
    cmd_m4a = [
      'ffmpeg', '-hide_banner', '-loglevel', 'error',
      '-y', '-i', input.path,
      '-vn', '-c:a', 'aac', '-b:a', '64k', '-ar', '44100',
      '-movflags', '+faststart',
      m4a.path
    ]
    _o, err_m4a, st_m4a = Open3.capture3(*cmd_m4a)
    if st_m4a.success? && File.size?(m4a.path)
      data = Base64.strict_encode64(File.binread(m4a.path))
      m4a.close!
      input.close!
      return [data, 'audio/mp4', 'voice.m4a']
    end
    Rails.logger.warn("[Evolution] audio transcode to m4a failed: #{err_m4a.to_s.truncate(200)}")
    m4a.close!

    # 2) Fallback ogg/opus
    ogg = Tempfile.new(['chatwoot_audio_out', '.ogg'])
    ogg.binmode
    cmd_ogg = [
      'ffmpeg', '-hide_banner', '-loglevel', 'error',
      '-y', '-i', input.path,
      '-vn', '-c:a', 'libopus', '-b:a', '24k', '-ar', '48000',
      ogg.path
    ]
    _o2, err_ogg, st_ogg = Open3.capture3(*cmd_ogg)
    unless st_ogg.success? && File.size?(ogg.path)
      Rails.logger.warn("[Evolution] audio transcode to ogg failed: #{err_ogg.to_s.truncate(300)}")
      ogg.close!
      input.close!
      return [nil, nil, nil]
    end

    data = Base64.strict_encode64(File.binread(ogg.path))
    ogg.close!
    input.close!
    [data, 'audio/ogg', 'voice.ogg']
  rescue Errno::ENOENT
    [nil, nil, nil]
  end
end
