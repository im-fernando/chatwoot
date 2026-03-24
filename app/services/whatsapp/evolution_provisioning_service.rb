# Provisions an Evolution API instance + webhook for unofficial WhatsApp (Baileys) inboxes.
# Requires EVOLUTION_API_MASTER_KEY and EVOLUTION_API_BASE_URL (or optional per-request api_base_url).
class Whatsapp::EvolutionProvisioningService
  # Subset aligned with Evolution API EventController.events (webhook schema enum); subscribe to all on inbox create.
  WEBHOOK_EVENTS = %w[
    APPLICATION_STARTUP
    CALL
    CHATS_DELETE
    CHATS_SET
    CHATS_UPDATE
    CHATS_UPSERT
    CONNECTION_UPDATE
    CONTACTS_SET
    CONTACTS_UPDATE
    CONTACTS_UPSERT
    GROUP_PARTICIPANTS_UPDATE
    GROUP_UPDATE
    GROUPS_UPSERT
    LABELS_ASSOCIATION
    LABELS_EDIT
    LOGOUT_INSTANCE
    MESSAGES_DELETE
    MESSAGES_SET
    MESSAGES_UPDATE
    MESSAGES_UPSERT
    PRESENCE_UPDATE
    QRCODE_UPDATED
    REMOVE_INSTANCE
    SEND_MESSAGE
    TYPEBOT_CHANGE_STATUS
    TYPEBOT_START
  ].freeze

  class ProvisioningError < StandardError; end

  def initialize(account:, inbox_name:, api_base_url: nil, phone_number: nil)
    @account = account
    @inbox_name = inbox_name.to_s
    @api_base_url = api_base_url.presence
    @phone_number_override = phone_number&.to_s&.strip.presence
  end

  def create_channel!
    raise ProvisioningError, I18n.t('errors.evolution.master_key_missing') if master_api_key.blank?

    instance_name = nil
    instance_api_key = nil

    begin
      instance_name = generate_unique_instance_name
      create_payload = create_remote_instance!(instance_name)
      instance_api_key = extract_instance_api_key(create_payload)
      set_remote_webhook!(instance_name, instance_api_key)

      @account.whatsapp_channels.create!(
        phone_number: resolved_phone_number,
        provider: 'evolution_api',
        provider_config: build_provider_config(instance_name, instance_api_key)
      )
    rescue StandardError => e
      delete_remote_instance(instance_name, instance_api_key) if instance_name.present?
      raise e
    end
  end

  private

  def master_api_key
    @master_api_key ||= ENV.fetch('EVOLUTION_API_MASTER_KEY', nil).presence
  end

  def base_url
    @base_url ||= @api_base_url.presence || ENV.fetch('EVOLUTION_API_BASE_URL', 'http://localhost:8080')
    @base_url.to_s.sub(%r{/$}, '')
  end

  def master_headers
    { 'apikey' => master_api_key, 'Content-Type' => 'application/json' }
  end

  def instance_headers(api_key)
    { 'apikey' => api_key, 'Content-Type' => 'application/json' }
  end

  def webhook_public_url
    explicit = ENV.fetch('EVOLUTION_WEBHOOK_PUBLIC_URL', nil).presence
    return explicit if explicit.present?

    "#{ENV.fetch('FRONTEND_URL', 'http://localhost:3000').to_s.chomp('/')}/webhooks/evolution"
  end

  # Nested `webhook` for POST /instance/create (optional) and must match what eventManager passes to DB.
  # POST /webhook/set validates against webhookSchema (Evolution 2.3.x): root requires key `webhook` with
  # `enabled` + `url` inside — see webhook.router.ts + webhook.schema.ts.
  def webhook_payload_for_create
    {
      'enabled' => true,
      'url' => webhook_public_url,
      'byEvents' => true,
      'base64' => true,
      'events' => WEBHOOK_EVENTS
    }
  end

  def instance_create_body(instance_name)
    wh = webhook_payload_for_create
    {
      'instanceName' => instance_name,
      'integration' => 'WHATSAPP-BAILEYS',
      # instance.schema.ts (Evolution) uses this key for the integration enum
      'Integration' => 'WHATSAPP-BAILEYS',
      'qrcode' => false,
      # OpenAPI / strict validators: nested `webhook`
      'webhook' => wh,
      # Same data as flat keys (instance.schema.ts + runtimes that map flat → eventManager)
      'webhookUrl' => wh['url'],
      'webhookByEvents' => wh['byEvents'],
      'webhookBase64' => wh['base64'],
      'webhookEvents' => wh['events']
    }
  end

  def generate_unique_instance_name
    5.times do
      name = build_instance_name_candidate
      return name unless instance_name_taken?(name)
    end

    "#{build_instance_name_candidate}-#{SecureRandom.hex(4)}"
  end

  def build_instance_name_candidate
    base = @inbox_name.parameterize(separator: '-').presence
    base = 'inbox' if base.blank?
    base = base.downcase.gsub(/[^a-z0-9-]/, '').gsub(/-+/, '-')
    base = base.delete_prefix('-').delete_suffix('-')
    base = 'inbox' if base.blank?
    base = base[0, 32]
    "#{base}-a#{@account.id}-#{SecureRandom.hex(3)}"
  end

  def instance_name_taken?(name)
    Channel::Whatsapp
      .where(provider: 'evolution_api')
      .where("provider_config->>'evolution_instance' = ?", name)
      .exists?
  end

  def resolved_phone_number
    return @phone_number_override if @phone_number_override.present?

    generate_placeholder_phone
  end

  def generate_placeholder_phone
    loop do
      candidate = "+1555#{SecureRandom.random_number(10_000_000).to_s.rjust(7, '0')}"
      return candidate unless Channel::Whatsapp.exists?(phone_number: candidate)
    end
  end

  def create_remote_instance!(instance_name)
    payload = instance_create_body(instance_name)
    json_body = JSON.generate(payload)

    code, body_text = post_json_to_evolution!('/instance/create', json_body)
    unless code >= 200 && code < 300
      Rails.logger.warn(
        "[EvolutionProvisioningService] /instance/create failed http=#{code} " \
        "payload_keys=#{payload.keys.sort.join(',')} webhook_present=#{payload.key?('webhook')}"
      )
      raise ProvisioningError, parse_evolution_error_body(code, body_text)
    end

    JSON.parse(body_text)
  rescue JSON::ParserError
    raise ProvisioningError, I18n.t('errors.evolution.provision_failed')
  rescue HTTParty::Error, SocketError, Errno::ECONNREFUSED, Errno::ETIMEDOUT, OpenSSL::SSL::SSLError,
         Timeout::Error => e
    raise ProvisioningError, evolution_network_error_message(e.message)
  end

  # Net::HTTP avoids HTTParty edge cases where JSON bodies are not sent as-is to some proxies.
  def post_json_to_evolution!(path, json_body)
    uri = URI.join("#{base_url}/", path.delete_prefix('/'))
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == 'https'
    http.read_timeout = 60
    http.open_timeout = 60

    req = Net::HTTP::Post.new(uri.request_uri)
    req['Content-Type'] = 'application/json; charset=utf-8'
    req['Accept'] = 'application/json'
    req['apikey'] = master_api_key
    req.body = json_body
    req['Content-Length'] = json_body.bytesize.to_s

    res = http.request(req)
    [res.code.to_i, res.body.to_s]
  end

  def extract_instance_api_key(payload)
    unless payload.is_a?(Hash)
      raise ProvisioningError,
            "#{I18n.t('errors.evolution.provision_failed')} (unexpected response type)"
    end

    key = extract_api_key_from_hash(payload.with_indifferent_access)
    raise ProvisioningError, I18n.t('errors.evolution.provision_failed') if key.blank?

    key.to_s
  end

  # Evolution v2 instance/create returns `hash` as the raw instance apikey string (UUID) in current
  # server code; older docs / builds used `hash: { apikey: "..." }`. See EvolutionAPI instance.controller
  # `createInstance` (returns `{ instance: {...}, hash, ... }` with hash as string).
  # Never use Hash#dig through keys that might be non-Hash intermediates.
  def extract_api_key_from_hash(p)
    %i[apikey apiKey token].each do |k|
      v = p[k]
      sk = normalize_api_key_string(v)
      return sk if sk.present?
    end

    raw_hash = p[:hash]
    if raw_hash.is_a?(String) && raw_hash.present?
      # Current Evolution API: instance token is the string value of `hash`
      return raw_hash.strip
    end

    data = p[:data]
    data = data.with_indifferent_access if data.is_a?(Hash)
    inst = p[:instance].presence || (data.is_a?(Hash) ? data[:instance] : nil)

    nested_hash_apikey(p[:hash]) ||
      nested_hash_apikey(data.is_a?(Hash) ? data[:hash] : nil) ||
      instance_object_apikey(inst)
  end

  def nested_hash_apikey(node)
    return nil unless node.is_a?(Hash)

    h = node.with_indifferent_access
    %i[apikey apiKey].each do |k|
      sk = normalize_api_key_string(h[k])
      return sk if sk.present?
    end
    nil
  end

  def instance_object_apikey(node)
    sk = nested_hash_apikey(node)
    return sk if sk.present?

    return nil unless node.is_a?(Hash)

    inst = node.with_indifferent_access
    %i[token apikey apiKey].each do |k|
      sk = normalize_api_key_string(inst[k])
      return sk if sk.present?
    end
    nil
  end

  def normalize_api_key_string(value)
    return nil if value.blank?
    return value.strip if value.is_a?(String)
    return value.to_s.strip if value.is_a?(Symbol)

    nil
  end

  def set_remote_webhook!(instance_name, instance_api_key)
    # Evolution webhookSchema: { "webhook": { "enabled", "url", ... } } — flat body fails validation.
    body = {
      'webhook' => webhook_payload_for_create
    }

    escaped = CGI.escape(instance_name)
    response = HTTParty.post(
      "#{base_url}/webhook/set/#{escaped}",
      headers: instance_headers(instance_api_key),
      body: body.to_json,
      timeout: 60
    )
    raise ProvisioningError, parse_evolution_error(response) unless response.success?

    nil
  rescue HTTParty::Error, SocketError, Errno::ECONNREFUSED, Errno::ETIMEDOUT, OpenSSL::SSL::SSLError,
         Timeout::Error => e
    raise ProvisioningError, evolution_network_error_message(e.message, label: 'Evolution API webhook')
  end

  def delete_remote_instance(instance_name, instance_api_key)
    escaped = CGI.escape(instance_name)
    key = instance_api_key.presence || master_api_key
    HTTParty.delete(
      "#{base_url}/instance/delete/#{escaped}",
      headers: { 'apikey' => key, 'Content-Type' => 'application/json' },
      timeout: 30
    )
  rescue StandardError => e
    Rails.logger.warn "[EvolutionProvisioningService] cleanup delete failed: #{e.message}"
  end

  def build_provider_config(instance_name, api_key)
    cfg = {
      'evolution_instance' => instance_name,
      'api_key' => api_key,
      'skip_connection_validation' => true
    }
    cfg['api_base_url'] = @api_base_url if @api_base_url.present?
    cfg
  end

  def evolution_network_error_message(original_message, label: 'Evolution API')
    msg = "#{label} (#{base_url}): #{original_message}"
    if original_message.to_s.match?(/getaddrinfo/i)
      msg += " #{I18n.t('errors.evolution.dns_unreachable_hint')}"
    end
    msg
  end

  def parse_evolution_error(response)
    parse_evolution_error_body(response.code, response.body.to_s)
  end

  # Evolution often returns { "status": 400, "error": "Bad Request", "response": { "message": ["..."] } }.
  # Prefer nested validation messages over the generic top-level "message".
  def parse_evolution_error_body(code, body)
    parsed = JSON.parse(body)
    message = extract_evolution_error_message(parsed)
    return message if message.present?

    "HTTP #{code}: #{body.to_s.truncate(400)}"
  rescue JSON::ParserError
    "HTTP #{code}: #{body.to_s.truncate(400)}"
  end

  def extract_evolution_error_message(parsed)
    return nil unless parsed.is_a?(Hash)

    nested = parsed.dig('response', 'message')
    nested = nested.join(', ') if nested.is_a?(Array)

    top = parsed['message']
    top = top.join(', ') if top.is_a?(Array)

    candidates = [nested, top, parsed['error']].compact.map(&:to_s).map(&:strip)
    candidates.find(&:present?)
  end
end
