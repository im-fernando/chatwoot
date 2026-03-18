# frozen_string_literal: true

# Fluxo de triagem WhatsApp: *Fiscal* e *Financeiro* indisponíveis 17h–6h59 (America/Sao_Paulo).
module Whatsapp
  class MenuTriageService
    TEAM_PDV_ID = 1
    TEAM_GERENCIAL_ID = 2
    TEAM_FISCAL_ID = 3
    TEAM_FINANCEIRO_ID = 4

    TIMEZONE = 'America/Sao_Paulo'

    attr_reader :conversation, :message

    def self.enabled_for_inbox?(inbox)
      inbox.whatsapp? && inbox.whatsapp_menu_triage_enabled?
    end

    def initialize(conversation, message)
      @conversation = conversation
      @message = message
    end

    def perform
      return unless self.class.enabled_for_inbox?(conversation.inbox)
      return unless conversation.inbox.channel_type == 'Channel::Whatsapp'
      return unless message.incoming?
      return if conversation.additional_attributes['whatsapp_menu_triage']&.dig('status') == 'completed'

      triage = conversation.additional_attributes['whatsapp_menu_triage'] || {}
      awaiting = triage['status'] == 'awaiting_choice'
      in_triage = conversation.pending? || awaiting
      return unless in_triage

      choice = parse_choice(message.content)

      if awaiting
        handle_awaiting(choice)
      else
        handle_first_touch(choice)
      end
    end

    def self.fiscal_financeiro_off_hours_now?
      tz = ActiveSupport::TimeZone[TIMEZONE]
      return false unless tz

      h = tz.now.hour
      h >= 17 || h < 7
    end

    private

    def formatted_protocol
      id = conversation.display_id.to_s
      padded = id.length >= 4 ? id : id.rjust(4, '0')
      "##{padded}"
    end

    def parse_choice(content)
      c = content.to_s.strip
      return c if %w[1 2 3 4].include?(c)

      nil
    end

    def after_hours_blocked_choice?(choice)
      %w[3 4].include?(choice) && self.class.fiscal_financeiro_off_hours_now?
    end

    def after_hours_unavailable_reply
      'Os setores ⚠️ *Fiscal* e ⚠️ *Financeiro* não estão em atendimento neste horário. Digite 1 ou 2.'
    end

    def handle_first_touch(choice)
      if after_hours_blocked_choice?(choice)
        send_reply(after_hours_unavailable_reply)
        mark_awaiting_choice
        return
      end

      if choice.present? && choice_valid_now?(choice)
        route_to(choice)
      else
        send_menu
      end
    end

    def handle_awaiting(choice)
      if choice.blank?
        send_invalid
        return
      end

      if after_hours_blocked_choice?(choice)
        send_reply(after_hours_unavailable_reply)
        return
      end

      if choice_valid_now?(choice)
        route_to(choice)
      else
        send_invalid
      end
    end

    def choice_valid_now?(choice)
      return false if choice.blank?
      return false if %w[3 4].include?(choice) && self.class.fiscal_financeiro_off_hours_now?

      %w[1 2 3 4].include?(choice)
    end

    def team_for(choice)
      case choice
      when '1' then TEAM_PDV_ID
      when '2' then TEAM_GERENCIAL_ID
      when '3' then TEAM_FISCAL_ID
      when '4' then TEAM_FINANCEIRO_ID
      end
    end

    def route_to(choice)
      team_id = team_for(choice)
      team_id = nil unless team_id.to_i.positive?

      attrs = conversation.additional_attributes.deep_dup
      attrs['whatsapp_menu_triage'] = { 'status' => 'completed' }

      updates = { status: :open, additional_attributes: attrs }
      updates[:team_id] = team_id if team_id
      conversation.update!(updates)

      send_reply(
        "Seu protocolo de atendimento é: #{formatted_protocol}. Aguarde que em breve você será atendido."
      )
    end

    def send_menu
      text = if self.class.fiscal_financeiro_off_hours_now?
               <<~TXT.strip
                 Olá! Escolha o assunto digitando o número:

                 1 — PDV/PAY (Sistema dos frentistas)
                 2 — Gerencial (Sistema de gerência do posto)
                 ⚠️ *Fiscal* — indisponível neste horário (atendimento das 7h às 16h59).
                 ⚠️ *Financeiro* — indisponível neste horário (atendimento das 7h às 16h59).
               TXT
             else
               <<~TXT.strip
                 Olá! Escolha o assunto digitando o número:

                 1 — PDV/PAY (Sistema dos frentistas)
                 2 — Gerencial (Sistema de gerência do posto)
                 3 — Fiscal
                 4 — Financeiro
               TXT
             end

      send_reply(text)
      mark_awaiting_choice
    end

    def mark_awaiting_choice
      attrs = conversation.additional_attributes.deep_dup
      attrs['whatsapp_menu_triage'] = { 'status' => 'awaiting_choice' }
      conversation.update!(additional_attributes: attrs)
    end

    def send_invalid
      hint = self.class.fiscal_financeiro_off_hours_now? ? '1 ou 2' : '1, 2, 3 ou 4'
      send_reply("Opção inválida. Digite #{hint}.")
    end

    def send_reply(text)
      Messages::MessageBuilder.new(nil, conversation.reload, { content: text, private: false }).perform
    end
  end
end
