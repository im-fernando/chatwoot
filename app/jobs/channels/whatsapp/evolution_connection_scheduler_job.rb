class Channels::Whatsapp::EvolutionConnectionSchedulerJob < ApplicationJob
  queue_as :low

  def perform
    Channel::Whatsapp.where(provider: 'evolution_api').each do |channel|
      Channels::Whatsapp::EvolutionConnectionSyncJob.perform_later(channel)
    end
  end
end
