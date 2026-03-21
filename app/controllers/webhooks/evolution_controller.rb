class Webhooks::EvolutionController < ActionController::API
  before_action :parse_evolution_payload

  def process_payload
    Rails.logger.info("Evolution webhook received: instance=#{@instance} event=#{@payload['event']}")
    channel = find_channel
    if channel.blank?
      Rails.logger.warn("Rejected Evolution webhook: no channel for instance #{@instance}")
      render json: { error: 'Channel not found' }, status: :not_found
      return
    end

    event = @payload['event'].presence || @payload[:event].presence
    bypass_inactivity = %w[connection.update logout.instance].include?(event.to_s)

    if !bypass_inactivity && channel_inactive?(channel)
      Rails.logger.warn("Rejected Evolution webhook for inactive channel: #{channel.phone_number}")
      render json: { error: 'Inactive channel' }, status: :unprocessable_content
      return
    end

    Webhooks::EvolutionEventsJob.perform_later(channel.id, @payload)
    head :ok
  end

  private

  def parse_evolution_payload
    @payload = if request.content_type&.include?('application/json') && request.raw_post.present?
                 ActiveSupport::JSON.decode(request.raw_post).with_indifferent_access
               else
                 request.parameters.except(:controller, :action).to_unsafe_h.with_indifferent_access
               end
    @instance = @payload['instance'].presence || @payload[:instance].presence
  end

  def find_channel
    return nil if @instance.blank?

    Channel::Whatsapp
      .where(provider: 'evolution_api')
      .where("provider_config->>'evolution_instance' = ?", @instance.to_s)
      .take
  end

  def channel_inactive?(channel)
    channel.reauthorization_required? || !channel.account.active?
  end
end
