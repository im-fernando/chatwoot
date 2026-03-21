class Webhooks::EvolutionEventsJob < ApplicationJob
  queue_as :low

  MESSAGES_UPSERT_EVENTS = %w[MESSAGES_UPSERT messages.upsert].freeze
  CONNECTION_UPDATE_EVENTS = %w[CONNECTION_UPDATE connection.update].freeze
  LOGOUT_INSTANCE_EVENTS = %w[LOGOUT_INSTANCE logout.instance].freeze

  def perform(channel_id, payload = {})
    channel = Channel::Whatsapp.find_by(id: channel_id, provider: 'evolution_api')
    if channel.blank?
      Rails.logger.warn("EvolutionEventsJob: channel #{channel_id} not found or not evolution_api")
      return
    end

    event = payload['event'].presence || payload[:event].presence

    if CONNECTION_UPDATE_EVENTS.include?(event.to_s)
      handle_connection_update(channel, payload)
      return
    elsif LOGOUT_INSTANCE_EVENTS.include?(event.to_s)
      handle_logout_instance(channel)
      return
    end

    if channel_is_inactive?(channel)
      Rails.logger.warn("Inactive Evolution channel: #{channel.phone_number}")
      return
    end

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

  def handle_connection_update(channel, payload)
    data = payload['data'].presence || payload[:data].presence || {}
    state = data['state'].presence || data[:state].presence
    
    case state.to_s
    when 'open'
      reactivate_channel!(channel)
    when 'close', 'refused'
      deactivate_channel!(channel)
    end
  end

  def handle_logout_instance(channel)
    deactivate_channel!(channel)
  end

  def reactivate_channel!(channel)
    if channel.reauthorization_required?
      Rails.logger.info("EvolutionEventsJob: Reconnecting channel #{channel.id}")
      channel.reauthorized!
    end
  end

  def deactivate_channel!(channel)
    unless channel.reauthorization_required?
      Rails.logger.warn("EvolutionEventsJob: Channel #{channel.id} is disconnected. Marking as reauthorization_required.")
      channel.prompt_reauthorization!
    end
  end

  def channel_is_inactive?(channel)
    channel.reauthorization_required? || !channel.account.active?
  end
end
