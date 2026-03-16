class Webhooks::EvolutionEventsJob < ApplicationJob
  queue_as :low

  MESSAGES_UPSERT_EVENTS = %w[MESSAGES_UPSERT messages.upsert].freeze

  def perform(channel_id, payload = {})
    channel = Channel::Whatsapp.find_by(id: channel_id, provider: 'evolution_api')
    if channel.blank?
      Rails.logger.warn("EvolutionEventsJob: channel #{channel_id} not found or not evolution_api")
      return
    end

    if channel_is_inactive?(channel)
      Rails.logger.warn("Inactive Evolution channel: #{channel.phone_number}")
      return
    end

    event = payload['event'].presence || payload[:event].presence
    unless MESSAGES_UPSERT_EVENTS.include?(event.to_s)
      return
    end

    data = payload['data'].presence || payload[:data].presence
    return if data.blank?

    # Skip messages sent by us (echo); optional: handle as outgoing_echo later
    key = data['key'].presence || data[:key].presence
    return if key && (key['fromMe'] || key[:fromMe])

    Whatsapp::IncomingMessageEvolutionService.new(inbox: channel.inbox, params: payload).perform
  end

  private

  def channel_is_inactive?(channel)
    channel.reauthorization_required? || !channel.account.active?
  end
end
