class Whatsapp::FetchEvolutionProfilePictureJob < ApplicationJob
  queue_as :low

  def perform(contact_id, channel_id)
    contact = Contact.find_by(id: contact_id)
    channel = Channel::Whatsapp.find_by(id: channel_id)
    return unless contact && channel
    return unless channel.provider == 'evolution_api'

    api_base_url = (channel.provider_config['api_base_url'].presence || ENV.fetch('EVOLUTION_API_BASE_URL', 'http://localhost:8080')).to_s.sub(%r{/$}, '')
    instance = channel.provider_config['evolution_instance'].to_s
    api_key = channel.provider_config['api_key']
    return if api_base_url.blank? || instance.blank?

    number = contact.phone_number.to_s.delete('+')

    response = HTTParty.post(
      "#{api_base_url}/chat/fetchProfilePictureUrl/#{CGI.escape(instance)}",
      headers: { 'apikey' => api_key, 'Content-Type' => 'application/json' },
      body: { number: number }.to_json
    )

    if response.success? && response.parsed_response['profilePictureUrl'].present?
      avatar_url = response.parsed_response['profilePictureUrl']
      Avatar::AvatarFromUrlJob.perform_later(contact, avatar_url)
    end
  rescue StandardError => e
    Rails.logger.error "FetchEvolutionProfilePictureJob failed: #{e.message}"
  end
end
