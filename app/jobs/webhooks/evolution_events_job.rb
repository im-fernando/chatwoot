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
      Rails.logger.debug("EvolutionEventsJob: ignoring event=#{event.inspect} (expected #{MESSAGES_UPSERT_EVENTS})")
      return
    end

    data = payload['data'].presence || payload[:data].presence
    if data.blank?
      Rails.logger.warn("EvolutionEventsJob: payload has no data")
      return
    end

    # Skip messages sent by us (echo); optional: handle as outgoing_echo later
    key = data['key'].presence || data[:key].presence
    if key && (key['fromMe'] || key[:fromMe])
      Rails.logger.debug("EvolutionEventsJob: skipping fromMe message")
      return
    end

    Rails.logger.info("EvolutionEventsJob: processing incoming message for channel #{channel_id}")
    Whatsapp::IncomingMessageEvolutionService.new(inbox: channel.inbox, params: payload).perform
  rescue StandardError => e
    Rails.logger.error("EvolutionEventsJob failed: #{e.class} #{e.message}\n#{e.backtrace.first(10).join("\n")}")
    raise
  end

  private

  def channel_is_inactive?(channel)
    channel.reauthorization_required? || !channel.account.active?
  end
end
