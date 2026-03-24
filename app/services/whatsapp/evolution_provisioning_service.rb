# Provisions an Evolution API instance + webhook for unofficial WhatsApp (Baileys) inboxes.
# Requires EVOLUTION_API_MASTER_KEY and EVOLUTION_API_BASE_URL (or optional per-request api_base_url).
class Whatsapp::EvolutionProvisioningService
  WEBHOOK_EVENTS = %w[
    MESSAGES_UPSERT
    MESSAGES_UPDATE
    CONNECTION_UPDATE
    QRCODE_UPDATED
  ].freeze

  class ProvisioningError < StandardError; end

  def initialize(account:, inbox_name:, api_base_url: nil)
    @account = account
    @inbox_name = inbox_name.to_s
    @api_base_url = api_base_url.presence
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
        phone_number: generate_placeholder_phone,
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

  def generate_placeholder_phone
    loop do
      candidate = "+1555#{SecureRandom.random_number(10_000_000).to_s.rjust(7, '0')}"
      return candidate unless Channel::Whatsapp.exists?(phone_number: candidate)
    end
  end

  def create_remote_instance!(instance_name)
    body = {
      'instanceName' => instance_name,
      'integration' => 'WHATSAPP-BAILEYS',
      'qrcode' => false
    }

    response = HTTParty.post(
      "#{base_url}/instance/create",
      headers: master_headers,
      body: body.to_json,
      timeout: 60
    )

    raise ProvisioningError, parse_evolution_error(response) unless response.success?

    response.parsed_response
  end

  def extract_instance_api_key(payload)
    key = payload.dig('hash', 'apikey').presence || payload.dig(:hash, :apikey).presence
    raise ProvisioningError, I18n.t('errors.evolution.provision_failed') if key.blank?

    key.to_s
  end

  def set_remote_webhook!(instance_name, instance_api_key)
    body = {
      'enabled' => true,
      'url' => webhook_public_url,
      'webhookByEvents' => true,
      'webhookBase64' => true,
      'events' => WEBHOOK_EVENTS
    }

    escaped = CGI.escape(instance_name)
    response = HTTParty.post(
      "#{base_url}/webhook/set/#{escaped}",
      headers: instance_headers(instance_api_key),
      body: body.to_json,
      timeout: 60
    )

    raise ProvisioningError, parse_evolution_error(response) unless response.success?
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

  def parse_evolution_error(response)
    parsed = response.parsed_response
    if parsed.is_a?(Hash)
      msg = parsed['message'] || parsed.dig('response', 'message')
      msg = msg.join(', ') if msg.is_a?(Array)
      msg = msg.to_s if msg.present?
      return msg if msg.present?
    end
    "HTTP #{response.code}: #{response.body.to_s.truncate(400)}"
  end
end
