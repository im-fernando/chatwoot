class Channels::Whatsapp::EvolutionConnectionSyncJob < ApplicationJob
  queue_as :low

  def perform(channel)
    return unless channel.provider == 'evolution_api'

    instance = channel.provider_config['evolution_instance'].to_s
    return if instance.blank?

    base_url = channel.provider_config['api_base_url'].presence || ENV.fetch('EVOLUTION_API_BASE_URL', 'http://localhost:8080')
    base_url = base_url.to_s.sub(%r{/$}, '')
    url = "#{base_url}/instance/connectionState/#{instance}"

    headers = channel.api_headers

    response = HTTParty.get(url, headers: headers, timeout: 10)

    # Se retornar 404, a instância não existe na API (foi apagada ou deslogada permanentemente)
    if response.code == 404
      deactivate_channel!(channel)
      return
    end

    return unless response.success?

    parsed = response.parsed_response
    instance_state = parsed['instance'] || parsed[:instance] || {}
    state = instance_state['state'] || instance_state[:state]

    case state.to_s
    when 'open'
      reactivate_channel!(channel)
    when 'close', 'refused'
      deactivate_channel!(channel)
    end
  rescue StandardError => e
    Rails.logger.error "[EvolutionConnectionSyncJob] Failed for channel #{channel.id}: #{e.class} #{e.message}"
  end

  private

  def reactivate_channel!(channel)
    if channel.reauthorization_required?
      Rails.logger.info("EvolutionConnectionSyncJob: Reconnecting channel #{channel.id}")
      channel.reauthorized!
    end
  end

  def deactivate_channel!(channel)
    unless channel.reauthorization_required?
      Rails.logger.warn("EvolutionConnectionSyncJob: Channel #{channel.id} is disconnected. Marking as reauthorization_required.")
      channel.prompt_reauthorization!
    end
  end
end
