require 'ruby_llm'

module Llm::Config
  DEFAULT_MODEL = 'gpt-4.1-mini'.freeze
  DEFAULT_GEMINI_API_BASE = 'https://generativelanguage.googleapis.com/v1beta'.freeze

  class << self
    def initialized?
      @initialized ||= false
    end

    def initialize!
      return if @initialized

      configure_ruby_llm
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

    private

    def configure_ruby_llm
      RubyLLM.configure do |config|
        config.openai_api_key = system_api_key('openai') if system_api_key('openai').present?
        config.openai_api_base = openai_endpoint.chomp('/') if openai_endpoint.present?

        config.gemini_api_key = system_api_key('gemini') if system_api_key('gemini').present?
        config.gemini_api_base = gemini_api_base if gemini_api_base.present?
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
        InstallationConfig.find_by(name: 'CAPTAIN_GEMINI_API_KEY')&.value
      else
        InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_API_KEY')&.value
      end
    end

    def openai_endpoint
      InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_ENDPOINT')&.value
    end

    def gemini_api_base
      InstallationConfig.find_by(name: 'CAPTAIN_GEMINI_API_BASE')&.value&.chomp('/')
    end
  end
end
