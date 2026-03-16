# Transforms Evolution API webhook payload into the format expected by IncomingMessageBaseService
# (contacts + messages with :id, :from, :type, :text => { body }, etc.)
# Evolution payload: event, instance, data => { key: { remoteJid, fromMe, id }, message: { conversation | imageMessage | ... }, pushName }
class Whatsapp::IncomingMessageEvolutionService < Whatsapp::IncomingMessageBaseService
  private

  def processed_params
    @processed_params ||= build_processed_params
  end

  def build_processed_params
    data = get_data
    return {} if data.blank?

    key = get_key(data)
    return {} if key.blank?

    msg = get_message(data)
    ev_type = evolution_message_type(msg)
    from_number = remote_jid_to_number(key['remoteJid'] || key[:remoteJid])
    push_name = data['pushName'].presence || data[:pushName].presence || from_number

    message_hash = build_message_hash(key, from_number, ev_type, msg)
    contacts_hash = [{ wa_id: from_number, profile: { name: push_name } }].with_indifferent_access

    { messages: [message_hash].with_indifferent_access, contacts: contacts_hash }.with_indifferent_access
  end

  def get_data
    params['data'].presence || params[:data].presence || {}
  end

  def get_key(data)
    data['key'].presence || data[:key].presence || {}
  end

  def get_message(data)
    data['message'].presence || data[:message].presence || {}
  end

  def remote_jid_to_number(remote_jid)
    return '' if remote_jid.blank?

    remote_jid.to_s.split('@').first.to_s
  end

  def evolution_message_type(msg)
    return 'text' if msg['conversation'].present? || msg[:conversation].present?
    return 'text' if msg['extendedTextMessage'].present? || msg[:extendedTextMessage].present?
    return 'image' if msg['imageMessage'].present? || msg[:imageMessage].present?
    return 'video' if msg['videoMessage'].present? || msg[:videoMessage].present?
    return 'audio' if msg['audioMessage'].present? || msg[:audioMessage].present?
    return 'audio' if msg['pttMessage'].present? || msg[:pttMessage].present?
    return 'document' if msg['documentMessage'].present? || msg[:documentMessage].present?
    return 'sticker' if msg['stickerMessage'].present? || msg[:stickerMessage].present?
    return 'location' if msg['locationMessage'].present? || msg[:locationMessage].present?
    return 'contacts' if msg['contactsArrayMessage'].present? || msg[:contactsArrayMessage].present?

    'text'
  end

  def build_message_hash(key, from_number, ev_type, msg)
    id = key['id'].presence || key[:id].presence
    msg_hash = {
      id: id,
      from: from_number,
      type: ev_type,
      timestamp: (params['messageTimestamp'] || params[:messageTimestamp]).to_s
    }

    case ev_type
    when 'text'
      msg_hash[:text] = { body: evolution_text_content(msg) }
    when 'image', 'video', 'audio', 'document', 'sticker'
      cap = evolution_caption(msg, ev_type)
      msg_hash[ev_type.to_sym] = cap.present? ? { id: id, caption: cap } : { id: id }
    when 'location'
      msg_hash['location'] = evolution_location(msg)
    when 'contacts'
      msg_hash['contacts'] = evolution_contacts(msg)
    else
      msg_hash[:text] = { body: evolution_text_content(msg).presence || '' }
    end

    msg_hash[:context] = { id: evolution_quoted_id(msg) } if evolution_quoted_id(msg).present?
    msg_hash.with_indifferent_access
  end

  def evolution_text_content(msg)
    msg['conversation'].presence || msg[:conversation].presence ||
      msg.dig('extendedTextMessage', 'text') || msg.dig(:extendedTextMessage, :text)
  end

  def evolution_caption(msg, ev_type)
    key = "#{ev_type}Message"
    sub = msg[key].presence || msg[key.to_sym].presence
    sub&.dig('caption') || sub&.dig(:caption)
  end

  def evolution_location(msg)
    loc = msg['locationMessage'].presence || msg[:locationMessage].presence || {}
    {
      'latitude' => loc['degreesLatitude'] || loc[:degreesLatitude],
      'longitude' => loc['degreesLongitude'] || loc[:degreesLongitude],
      'name' => loc['name'] || loc[:name],
      'address' => loc['address'] || loc[:address],
      'url' => loc['url'] || loc[:url]
    }.compact
  end

  def evolution_contacts(msg)
    arr = msg['contactsArrayMessage'].presence || msg[:contactsArrayMessage].presence
    contacts = arr&.dig('contacts') || arr&.dig(:contacts) || []
    contacts.map do |c|
      name = c['name'] || c[:name] || {}
      { 'name' => { 'formatted_name' => name['formattedName'] || name[:formattedName] }, 'phones' => [] }
    end
  end

  def evolution_quoted_id(msg)
    ext = msg['extendedTextMessage'].presence || msg[:extendedTextMessage].presence
    ctx = ext&.dig('contextInfo') || ext&.dig(:contextInfo)
    ctx&.dig('stanzaId') || ctx&.dig(:stanzaId)
  end

  def download_attachment_file(attachment_payload)
    return nil if attachment_payload.blank?

    message_id = attachment_payload['id'].presence || attachment_payload[:id].presence
    return nil if message_id.blank?

    base_url = inbox.channel.provider_config['api_base_url'].presence || ENV.fetch('EVOLUTION_API_BASE_URL', 'http://localhost:8080')
    base_url = base_url.to_s.sub(%r{/$}, '')
    instance = inbox.channel.provider_config['evolution_instance'].to_s
    url = "#{base_url}/chat/getBase64FromMediaMessage/#{instance}"

    response = HTTParty.post(
      url,
      headers: inbox.channel.api_headers,
      body: { message: { key: { id: message_id } }, convertToMp4: false }.to_json
    )

    return nil unless response.success?

    parsed = response.parsed_response
    base64_data = parsed['base64'].presence || parsed[:base64].presence
    return nil if base64_data.blank?

    decoded = Base64.decode64(base64_data)
    ext = content_extension(attachment_payload)
    temp = Tempfile.new(['evolution_media', ".#{ext}"])
    temp.binmode
    temp.write(decoded)
    temp.rewind
    temp
  rescue StandardError => e
    Rails.logger.error "[Evolution] Failed to download media: #{e.message}"
    nil
  end

  def content_extension(attachment_payload)
    # message_type is e.g. 'image', 'video'; use a simple default
    type = messages_data&.first&.dig(:type).to_s
    { 'image' => 'jpg', 'video' => 'mp4', 'audio' => 'ogg', 'document' => 'bin', 'sticker' => 'webp' }[type] || 'bin'
  end
end
