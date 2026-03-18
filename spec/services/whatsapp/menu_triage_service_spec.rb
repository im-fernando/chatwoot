# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Whatsapp::MenuTriageService do
  let(:account) { create(:account) }
  let(:channel) { create(:channel_whatsapp, account: account) }
  let(:inbox) do
    i = account.inboxes.find_by!(channel: channel)
    i.update!(whatsapp_menu_triage_enabled: true)
    i
  end
  let(:contact) { create(:contact, account: account) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox) }
  let(:conversation) do
    create(:conversation, account: account, inbox: inbox, contact_inbox: contact_inbox, contact: contact, status: :pending)
  end

  let(:team_pdv) { create(:team, account: account) }
  let(:team_ger) { create(:team, account: account) }
  let(:team_fiscal) { create(:team, account: account) }
  let(:team_fin) { create(:team, account: account) }

  def build_message(content)
    create(:message, conversation: conversation, inbox: inbox, account: account, message_type: :incoming,
                     sender: contact, content: content)
  end

  before do
    allow(SendReplyJob).to receive(:perform_later)
    stub_const('Whatsapp::MenuTriageService::TEAM_PDV_ID', team_pdv.id)
    stub_const('Whatsapp::MenuTriageService::TEAM_GERENCIAL_ID', team_ger.id)
    stub_const('Whatsapp::MenuTriageService::TEAM_FISCAL_ID', team_fiscal.id)
    stub_const('Whatsapp::MenuTriageService::TEAM_FINANCEIRO_ID', team_fin.id)
  end

  describe '#perform' do
    it 'does nothing when disabled for inbox' do
      inbox.update!(whatsapp_menu_triage_enabled: false)
      msg = build_message('oi')
      expect { described_class.new(conversation, msg).perform }.not_to(change { conversation.reload.messages.outgoing.count })
    end

    it 'sends menu on first non-choice message' do
      msg = build_message('olá')
      described_class.new(conversation, msg).perform
      conversation.reload
      expect(conversation.additional_attributes['whatsapp_menu_triage']['status']).to eq('awaiting_choice')
      expect(conversation.messages.outgoing.last.content).to include('PDV/PAY')
    end

    it 'routes immediately when first message is 1' do
      msg = build_message('1')
      described_class.new(conversation, msg).perform
      conversation.reload
      expect(conversation).to be_open
      expect(conversation.team_id).to eq(team_pdv.id)
      expect(conversation.additional_attributes['whatsapp_menu_triage']['status']).to eq('completed')
    end

    it 'includes padded protocol (# + zeros) in confirmation' do
      msg = build_message('4')
      described_class.new(conversation, msg).perform
      did = conversation.reload.display_id
      padded = did.to_s.length >= 4 ? did.to_s : did.to_s.rjust(4, '0')
      expect(conversation.messages.outgoing.last.content).to include("##{padded}")
    end

    it 'routes 4 to financeiro team' do
      msg = build_message('4')
      described_class.new(conversation, msg).perform
      expect(conversation.reload.team_id).to eq(team_fin.id)
    end

    it 'rejects invalid option when awaiting' do
      conversation.update!(additional_attributes: { 'whatsapp_menu_triage' => { 'status' => 'awaiting_choice' } })
      msg = build_message('9')
      described_class.new(conversation, msg).perform
      expect(conversation.messages.outgoing.last.content).to include('inválida')
    end

    it 'routes 2 after menu' do
      conversation.update!(additional_attributes: { 'whatsapp_menu_triage' => { 'status' => 'awaiting_choice' } })
      msg = build_message('2')
      described_class.new(conversation, msg).perform
      conversation.reload
      expect(conversation.team_id).to eq(team_ger.id)
      expect(conversation).to be_open
    end

    context 'when fiscal and financeiro are offline (18:00 America/Sao_Paulo)' do
      around do |example|
        tz = ActiveSupport::TimeZone['America/Sao_Paulo']
        travel_to(tz.local(2025, 6, 15, 18, 0, 0)) { example.run }
      end

      it 'shows *Fiscal* and *Financeiro* as unavailable in menu' do
        msg = build_message('oi')
        described_class.new(conversation, msg).perform
        body = conversation.messages.outgoing.last.content
        expect(body).to include('*Fiscal*')
        expect(body).to include('*Financeiro*')
      end

      it 'blocks choice 3 or 4' do
        conversation.update!(additional_attributes: { 'whatsapp_menu_triage' => { 'status' => 'awaiting_choice' } })
        msg = build_message('4')
        described_class.new(conversation, msg).perform
        expect(conversation.messages.outgoing.last.content).to include('*Fiscal*')
        expect(conversation.messages.outgoing.last.content).to include('*Financeiro*')
        expect(conversation.reload).to be_pending
      end
    end
  end
end
