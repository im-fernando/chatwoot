# Evolution/Baileys interactive payloads (buttons, lists, templates and their replies) carry
# their text outside of `conversation`/`extendedTextMessage`, so they reach Chatwoot as an
# empty bubble unless it is extracted here. `text_for` returns the prompt text (or the chosen
# option, for replies) and `options_for` the offered options, which the dashboard renders as
# clickable chips.
module Whatsapp::EvolutionInteractiveContent
  module_function

  # Returns the message body for an interactive payload, or nil when `msg` isn't one.
  def text_for(msg)
    prompt_text(msg) || reply_text(msg)
  end

  # Returns [{ 'title' => String, 'url' => String? }] for payloads that offer options.
  def options_for(msg)
    if (sub = fetch(msg, 'buttonsMessage'))
      button_options(sub)
    elsif (sub = fetch(msg, 'listMessage'))
      list_options(sub)
    elsif (sub = fetch(msg, 'interactiveMessage'))
      native_flow_options(sub)
    elsif (sub = fetch(msg, 'templateMessage'))
      template_options(hydrated_template(sub))
    else
      []
    end
  end

  def prompt_text(msg)
    if (sub = fetch(msg, 'buttonsMessage'))
      fetch(sub, 'contentText')
    elsif (sub = fetch(msg, 'listMessage'))
      fetch(sub, 'description')
    elsif (sub = fetch(msg, 'interactiveMessage'))
      fetch(fetch(sub, 'body'), 'text')
    elsif (sub = fetch(msg, 'templateMessage'))
      fetch(hydrated_template(sub), 'hydratedContentText')
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

  def template_options(template)
    Array(fetch(template, 'hydratedButtons')).filter_map do |button|
      hydrated = fetch(button, 'quickReplyButton') || fetch(button, 'urlButton') || fetch(button, 'callButton')
      option(fetch(hydrated, 'displayText'), fetch(hydrated, 'url'))
    end
  end

  def hydrated_template(sub)
    fetch(sub, 'hydratedTemplate') || fetch(sub, 'hydratedFourRowTemplate')
  end

  def option(title, url = nil)
    return nil if title.blank?

    { 'title' => title, 'url' => url.presence }.compact
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
