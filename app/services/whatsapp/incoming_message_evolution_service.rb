# Transforms Evolution API webhook payload into the format expected by IncomingMessageBaseService
# (contacts + messages with :id, :from, :type, :text => { body }, etc.)
# Evolution payload: event, instance, data => { key: { remoteJid, fromMe, id }, message: { conversation | imageMessage | ... }, pushName }
class Whatsapp::IncomingMessageEvolutionService < Whatsapp::IncomingMessageBaseService
  CSAT_RATING_EMOJIS = %w[😞 😑 😐 😀 😍].freeze
  # Payloads that carry the quoted message they reply to. Button/list replies quote the
  # prompt they came from, so reading them keeps the reply threaded like WhatsApp shows it.
  QUOTING_MESSAGE_KEYS = %w[extendedTextMessage buttonsResponseMessage listResponseMessage templateButtonReplyMessage].freeze

  private

  def set_conversation
    # Default behavior (in base) creates a new conversation for each incoming message
    # when lock_to_single_conversation is disabled and the last conversation is resolved.
    #
    # For CSAT text-flow (Baileys/Evolution), the next incoming message after the CSAT
    # prompt should be interpreted as the rating/feedback reply. So we reuse the
    # most recent resolved conversation with an active csat_text_flow state — but
    # only if the incoming message matches the expected reply for that step.
    if csat_text_flow_enabled?
      flow_conversation = latest_csat_text_flow_conversation_for(incoming_text_body)
      if flow_conversation.present?
        @conversation = flow_conversation
        return
      end
    end

    super
  end

  def csat_text_flow_enabled?
    inbox.channel.try(:provider) == 'evolution_api' && inbox.csat_config&.dig('text_flow_enabled') == true
  end

  def latest_csat_text_flow_conversation_for(body)
    @contact_inbox.conversations.order(created_at: :desc).find do |c|
      next unless c.resolved?

      flow = c.additional_attributes.is_a?(Hash) ? c.additional_attributes['csat_text_flow'] : nil
      next unless flow.is_a?(Hash)

      state = flow['state'].to_s
      next unless %w[await_rating await_feedback_optin await_feedback_text].include?(state)

      if matches_csat_text_flow_reply?(state, body)
        true
      else
        # If customer sends something else, clear flow so the message becomes a
        # normal conversation (new conversation will be created by base logic).
        clear_csat_text_flow!(c)
        false
      end
    end
  end

  def incoming_text_body
    msg = messages_data&.first
    return nil if msg.blank?

    type = msg[:type].to_s
    return nil unless type == 'text'

    msg.dig(:text, :body).to_s.strip.downcase
  end

  def matches_csat_text_flow_reply?(state, body)
    return false if body.blank?

    case state
    when 'await_rating'
      return true if body.match?(/\A[1-5]\z/)
      return true if CSAT_RATING_EMOJIS.include?(body)

      # If the customer sends a single character (e.g. an emoji or a typo),
      # keep it in the CSAT flow so we can respond with an "invalid option"
      # message instead of clearing the flow and opening a new conversation.
      body.scan(/\X/).length == 1
    when 'await_feedback_optin'
      %w[sim s yes y nao não n no].include?(body)
    when 'await_feedback_text'
      body.present?
    else
      false
    end
  end

  def clear_csat_text_flow!(conversation)
    attrs = conversation.additional_attributes.is_a?(Hash) ? conversation.additional_attributes : {}
    return unless attrs.key?('csat_text_flow')

    attrs.delete('csat_text_flow')
    conversation.update!(additional_attributes: attrs)
  end

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
    remote_number = remote_jid_to_number(key['remoteJid'] || key[:remoteJid])
    push_name = data['pushName'].presence || data[:pushName].presence || remote_number

    message_hash = build_message_hash(key, remote_number, ev_type, msg)

    if outgoing_echo
      # Echo payloads don't include contacts; IncomingMessageBaseService will use :to to build contact.
      channel_number = inbox.channel.phone_number.to_s.gsub(/\D/, '')
      message_hash[:from] = channel_number
      message_hash[:to] = remote_number
      { message_echoes: [message_hash] }.with_indifferent_access
    else
      contacts_hash = [{ wa_id: remote_number, profile: { name: push_name } }.with_indifferent_access]
      { messages: [message_hash], contacts: contacts_hash }.with_indifferent_access
    end
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
    return 'contacts' if msg['contactMessage'].present? || msg[:contactMessage].present?
    return reaction_message_type(msg) if evolution_reaction(msg).present?

    'text'
  end

  def evolution_reaction(msg)
    msg['reactionMessage'].presence || msg[:reactionMessage].presence
  end

  # A reaction is rendered as its emoji, quoting the message it reacts to. Removing a reaction
  # sends the same payload with a blank emoji, and 'reaction' is what the base service skips.
  def reaction_message_type(msg)
    evolution_reaction_emoji(msg).present? ? 'text' : 'reaction'
  end

  def evolution_reaction_emoji(msg)
    reaction = evolution_reaction(msg)
    return '' if reaction.blank?

    (reaction['text'] || reaction[:text]).to_s
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
      payload = { id: id }
      payload[:caption] = cap if cap.present?

      message_content = msg["#{ev_type}Message"] || msg["#{ev_type}Message".to_sym] || {}
      filename = message_content['fileName'] || message_content[:fileName]
      mimetype = message_content['mimetype'] || message_content[:mimetype]

      payload[:filename] = filename if filename.present?
      payload[:mimetype] = mimetype if mimetype.present?

      msg_hash[ev_type.to_sym] = payload
    when 'location'
      msg_hash['location'] = evolution_location(msg)
    when 'contacts'
      msg_hash['contacts'] = evolution_contacts(msg)
    else
      msg_hash[:text] = { body: evolution_text_content(msg).presence || '' }
    end

    options = Whatsapp::EvolutionInteractiveContent.options_for(msg)
    msg_hash[:interactive_options] = options if options.present?

    msg_hash[:context] = { id: evolution_quoted_id(msg) } if evolution_quoted_id(msg).present?
    msg_hash.with_indifferent_access
  end

  # Carries the offered options into content_attributes so the dashboard can render them as
  # clickable chips instead of losing them.
  def message_content_attributes(message)
    options = message[:interactive_options].presence || message['interactive_options'].presence
    return super if options.blank?

    super.merge(interactive_options: options)
  end

  def evolution_text_content(msg)
    msg['conversation'].presence || msg[:conversation].presence ||
      msg.dig('extendedTextMessage', 'text') || msg.dig(:extendedTextMessage, :text) ||
      evolution_reaction_emoji(msg).presence ||
      Whatsapp::EvolutionInteractiveContent.text_for(msg)
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
    contacts = []
    
    if msg['contactsArrayMessage'].present? || msg[:contactsArrayMessage].present?
      arr = msg['contactsArrayMessage'].presence || msg[:contactsArrayMessage].presence
      contacts = arr&.dig('contacts') || arr&.dig(:contacts) || []
    elsif msg['contactMessage'].present? || msg[:contactMessage].present?
      contacts = [msg['contactMessage'].presence || msg[:contactMessage].presence]
    end

    contacts.map do |c|
      display_name = c['displayName'] || c[:displayName]
      name_obj = c['name'] || c[:name] || {}
      formatted_name = display_name || name_obj['formattedName'] || name_obj[:formattedName] || 'Contato'
      vcard = c['vcard'] || c[:vcard]
      
      phones = []
      if vcard.present?
        # Extract phones from VCARD
        phones = vcard.scan(/TEL[^:]*:(.+)/i).flatten.map { |p| { 'phone' => p.strip } }
      end

      { 
        'name' => { 'first_name' => formatted_name, 'last_name' => '' }, 
        'phones' => phones
      }
    end
  end

  def evolution_quoted_id(msg)
    reaction = evolution_reaction(msg)
    if reaction.present?
      reacted_key = reaction['key'] || reaction[:key]
      return reacted_key&.dig('id') || reacted_key&.dig(:id)
    end

    QUOTING_MESSAGE_KEYS.each do |key|
      sub = msg[key].presence || msg[key.to_sym].presence
      next if sub.blank?

      ctx = sub['contextInfo'] || sub[:contextInfo]
      stanza_id = ctx&.dig('stanzaId') || ctx&.dig(:stanzaId)
      return stanza_id if stanza_id.present?
    end

    nil
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
    
    filename = attachment_payload[:filename].presence || attachment_payload['filename'].presence
    temp_name = filename.present? ? [File.basename(filename, ".*"), ".#{ext}"] : ['evolution_media', ".#{ext}"]

    temp = Tempfile.new(temp_name)
    temp.binmode
    temp.write(decoded)
    temp.rewind

    if filename.present?
      temp.define_singleton_method(:original_filename) do
        filename
      end
    end

    mimetype = attachment_payload[:mimetype].presence || attachment_payload['mimetype'].presence
    if mimetype.present?
      temp.define_singleton_method(:content_type) do
        mimetype
      end
    end

    temp
  rescue StandardError => e
    Rails.logger.error "[Evolution] Failed to download media: #{e.message}"
    nil
  end

  def content_extension(attachment_payload)
    filename = attachment_payload[:filename].presence || attachment_payload['filename'].presence
    return filename.split('.').last if filename.present? && filename.include?('.')

    # message_type is e.g. 'image', 'video'; use a simple default
    type = messages_data&.first&.dig(:type).to_s
    { 'image' => 'jpg', 'video' => 'mp4', 'audio' => 'ogg', 'document' => 'pdf', 'sticker' => 'webp' }[type] || 'bin'
  end
end
