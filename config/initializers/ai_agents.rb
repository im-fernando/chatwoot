# frozen_string_literal: true

require 'agents'

Rails.application.config.after_initialize do
  # Em um banco recém-criado (ex.: após `docker compose down -v`), as migrations ainda não rodaram
  # e a tabela `installation_configs` não existe. Além disso, tasks `db:*` carregam o app e
  # este initializer não deve bloquear o bootstrap do banco.
  if defined?(Rake) && Rake.respond_to?(:application)
    top_level = Rake.application.top_level_tasks
    next if top_level.any? { |t| t.to_s.start_with?('db:') }
  end

  openai_api_key = InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_API_KEY')&.value
  gemini_api_key = InstallationConfig.find_by(name: 'CAPTAIN_GEMINI_API_KEY')&.value
  model = InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_MODEL')&.value.presence || LlmConstants::DEFAULT_MODEL
  api_endpoint = InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_ENDPOINT')&.value || LlmConstants::OPENAI_API_ENDPOINT
  gemini_api_base = InstallationConfig.find_by(name: 'CAPTAIN_GEMINI_API_BASE')&.value&.chomp('/')

  if openai_api_key.present? || gemini_api_key.present?
    Agents.configure do |config|
      config.openai_api_key = openai_api_key if openai_api_key.present?
      if api_endpoint.present?
        api_base = "#{api_endpoint.chomp('/')}/v1"
        config.openai_api_base = api_base
      end
      config.gemini_api_key = gemini_api_key if gemini_api_key.present?
      config.gemini_api_base = gemini_api_base if gemini_api_base.present?
      config.default_model = model
      config.debug = false
    end
  end
rescue ActiveRecord::StatementInvalid, ActiveRecord::NoDatabaseError => e
  Rails.logger.warn("Skipping AI Agents SDK configuration (db not ready): #{e.class}: #{e.message}")
rescue StandardError => e
  Rails.logger.error "Failed to configure AI Agents SDK: #{e.message}"
end
