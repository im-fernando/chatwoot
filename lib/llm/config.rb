require 'ruby_llm'

module Llm::Config
  DEFAULT_MODEL = 'gpt-4.1-mini'.freeze
  DEFAULT_GEMINI_API_BASE = 'https://generativelanguage.googleapis.com/v1beta'.freeze

  class << self
    def initialized?
      @initialized ||= false
    end

    # Re-applies provider keys from the DB on every call. Installation configs can change at runtime
    # (Super Admin); caching once caused stale keys until process restart (e.g. Gemini added after boot).
    def initialize!
      configure_ruby_llm
      configure_agents_sdk!
      @initialized = true
    end

    def reset!
      @initialized = false
    end

    def with_api_key(api_key, provider: 'openai', api_base: nil)
      context = RubyLLM.context do |config|
        apply_provider_config(config, provider.to_s, api_key: api_key, api_base: api_base)
      end

      yield context
    end

    def configure_agents_sdk!
      require 'agents'

      openai_api_key = InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_API_KEY')&.value.presence || ENV.fetch('CAPTAIN_OPEN_AI_API_KEY', nil)
      gemini_api_key = InstallationConfig.find_by(name: 'CAPTAIN_GEMINI_API_KEY')&.value.presence || ENV.fetch('CAPTAIN_GEMINI_API_KEY', nil)
      return unless openai_api_key.present? || gemini_api_key.present?

      model = InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_MODEL')&.value.presence || LlmConstants::DEFAULT_MODEL
      api_endpoint = InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_ENDPOINT')&.value.presence || ENV.fetch('CAPTAIN_OPEN_AI_ENDPOINT', nil) || LlmConstants::OPENAI_API_ENDPOINT
      gemini_base = (InstallationConfig.find_by(name: 'CAPTAIN_GEMINI_API_BASE')&.value.presence || ENV.fetch('CAPTAIN_GEMINI_API_BASE', nil))&.chomp('/')

      Agents.configure do |config|
        config.openai_api_key = openai_api_key.presence
        if api_endpoint.present?
          api_base = "#{api_endpoint.chomp('/')}/v1"
          config.openai_api_base = api_base
        end
        config.gemini_api_key = gemini_api_key.presence
        config.gemini_api_base = gemini_base if gemini_base.present?
        config.default_model = model
        config.debug = false
      end
    rescue LoadError
      # ai-agents optional in some environments
      nil
    end

    private

    def configure_ruby_llm
      RubyLLM.configure do |config|
        openai_k = system_api_key('openai')
        config.openai_api_key = openai_k.presence

        ep = openai_endpoint
        config.openai_api_base = ep.present? ? ep.chomp('/') : nil

        gemini_k = system_api_key('gemini')
        config.gemini_api_key = gemini_k.presence
        config.gemini_api_base = gemini_api_base.presence || DEFAULT_GEMINI_API_BASE
        config.logger = Rails.logger
      end
    end

    def apply_provider_config(config, provider, api_key:, api_base:)
      case provider
      when 'gemini', 'google'
        config.gemini_api_key = api_key
        config.gemini_api_base = (api_base.presence || gemini_api_base.presence || DEFAULT_GEMINI_API_BASE)
      else
        config.openai_api_key = api_key
        config.openai_api_base = api_base
      end
    end

    def system_api_key(provider)
      case provider.to_s
      when 'gemini', 'google'
        InstallationConfig.find_by(name: 'CAPTAIN_GEMINI_API_KEY')&.value.presence || ENV.fetch('CAPTAIN_GEMINI_API_KEY', nil)
      else
        InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_API_KEY')&.value.presence || ENV.fetch('CAPTAIN_OPEN_AI_API_KEY', nil)
      end
    end

    def openai_endpoint
      InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_ENDPOINT')&.value.presence || ENV.fetch('CAPTAIN_OPEN_AI_ENDPOINT', nil)
    end

    def gemini_api_base
      (InstallationConfig.find_by(name: 'CAPTAIN_GEMINI_API_BASE')&.value.presence || ENV.fetch('CAPTAIN_GEMINI_API_BASE', nil))&.chomp('/')
    end
  end
end
