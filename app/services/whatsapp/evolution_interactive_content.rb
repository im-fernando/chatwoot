# Evolution/Baileys interactive payloads (buttons, lists, templates and their replies) carry
# their text outside of `conversation`/`extendedTextMessage`, so they reach Chatwoot as an
# empty bubble unless it is extracted here. Renders the prompt text followed by the offered
# options, and the chosen option for replies.
module Whatsapp::EvolutionInteractiveContent
  OPTION_PREFIX = '▸'.freeze

  module_function

  # Returns the message body for an interactive payload, or nil when `msg` isn't one.
  def text_for(msg)
    prompt_text(msg) || reply_text(msg)
  end

  def prompt_text(msg)
    if (sub = fetch(msg, 'buttonsMessage'))
      compose(fetch(sub, 'contentText'), button_options(sub))
    elsif (sub = fetch(msg, 'listMessage'))
      compose(fetch(sub, 'description'), list_options(sub))
    elsif (sub = fetch(msg, 'interactiveMessage'))
      compose(fetch(fetch(sub, 'body'), 'text'), native_flow_options(sub))
    elsif (sub = fetch(msg, 'templateMessage'))
      template_text(sub)
    end
  end

  def reply_text(msg)
    if (sub = fetch(msg, 'buttonsResponseMessage'))
      fetch(sub, 'selectedDisplayText') || fetch(sub, 'selectedButtonId')
    elsif (sub = fetch(msg, 'listResponseMessage'))
      fetch(sub, 'title') || fetch(fetch(sub, 'singleSelectReply'), 'selectedRowId')
    elsif (sub = fetch(msg, 'templateButtonReplyMessage'))
      fetch(sub, 'selectedDisplayText') || fetch(sub, 'selectedId')
    end
  end

  def button_options(sub)
    Array(fetch(sub, 'buttons')).filter_map do |button|
      option(fetch(fetch(button, 'buttonText'), 'displayText') || fetch(button, 'buttonId'))
    end
  end

  def list_options(sub)
    Array(fetch(sub, 'sections')).flat_map do |section|
      Array(fetch(section, 'rows')).filter_map { |row| option(fetch(row, 'title') || fetch(row, 'rowId')) }
    end
  end

  def native_flow_options(sub)
    Array(fetch(fetch(sub, 'nativeFlowMessage'), 'buttons')).filter_map do |button|
      params = parse_button_params(fetch(button, 'buttonParamsJson'))
      option(params['display_text'], params['url'])
    end
  end

  def template_text(sub)
    template = fetch(sub, 'hydratedTemplate') || fetch(sub, 'hydratedFourRowTemplate')
    options = Array(fetch(template, 'hydratedButtons')).filter_map do |button|
      hydrated = fetch(button, 'quickReplyButton') || fetch(button, 'urlButton') || fetch(button, 'callButton')
      option(fetch(hydrated, 'displayText'), fetch(hydrated, 'url'))
    end

    compose(fetch(template, 'hydratedContentText'), options)
  end

  def compose(text, options)
    [text.presence, options.presence&.join("\n")].compact.join("\n\n").presence
  end

  def option(label, url = nil)
    return nil if label.blank?

    url.present? ? "#{OPTION_PREFIX} #{label}: #{url}" : "#{OPTION_PREFIX} #{label}"
  end

  # buttonParamsJson is a JSON string built by the sender, so a malformed one should only
  # cost us that option rather than the whole message body.
  def parse_button_params(raw)
    return {} if raw.blank?

    JSON.parse(raw)
  rescue JSON::ParserError
    {}
  end

  def fetch(hash, key)
    return nil unless hash.is_a?(Hash)

    hash[key].presence || hash[key.to_sym].presence
  end
end
