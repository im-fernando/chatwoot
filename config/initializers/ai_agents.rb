# frozen_string_literal: true

# `agents` is required inside Llm::Config.configure_agents_sdk! to avoid load-order issues.

Rails.application.config.after_initialize do
  # Em um banco recém-criado (ex.: após `docker compose down -v`), as migrations ainda não rodaram
  # e a tabela `installation_configs` não existe. Além disso, tasks `db:*` carregam o app e
  # este initializer não deve bloquear o bootstrap do banco.
  if defined?(Rake) && Rake.respond_to?(:application)
    top_level = Rake.application.top_level_tasks
    next if top_level.any? { |t| t.to_s.start_with?('db:') }
  end

  Llm::Config.initialize!
rescue ActiveRecord::StatementInvalid, ActiveRecord::NoDatabaseError => e
  Rails.logger.warn("Skipping LLM / AI Agents configuration (db not ready): #{e.class}: #{e.message}")
rescue StandardError => e
  Rails.logger.error "Failed to configure LLM / AI Agents: #{e.message}"
end
