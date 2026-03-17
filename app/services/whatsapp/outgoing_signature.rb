# frozen_string_literal: true

module Whatsapp
  # Prepends outgoing WhatsApp text/captions with "> Agent Name" so mobile and web match.
  module OutgoingSignature
    module_function

    def line_for(message)
      user = message.sender
      return nil unless user.is_a?(User)

      name = user.try(:available_name).presence || user.try(:name).presence
      return nil if name.blank?

      "> #{name}"
    end

    def trim_body(text)
      text.to_s.gsub(/\n+\z/, '').strip
    end

    def combine_signature_and_body(sig, raw_trimmed)
      return raw_trimmed if sig.blank?
      return sig if raw_trimmed.blank?

      "#{sig}\n#{raw_trimmed}"
    end

    # Full body for plain text and media captions (image, video, document).
    def body_for_whatsapp(message)
      combine_signature_and_body(line_for(message), trim_body(message.outgoing_content))
    end

    # Interactive / quick-reply style messages (outgoing_content or item titles).
    def body_for_whatsapp_interactive(message)
      raw =
        message.outgoing_content.to_s.presence ||
        message.content_attributes['items']&.map { |i| i['title'] }&.join(', ')
      combine_signature_and_body(line_for(message), trim_body(raw.to_s))
    end
  end
end
