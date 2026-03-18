# == Schema Information
#
# Table name: ticket_conversations
#
#  id                :bigint           not null, primary key
#  support_ticket_id :bigint           not null
#  conversation_id   :bigint           not null
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#
class TicketConversation < ApplicationRecord
  belongs_to :support_ticket
  belongs_to :conversation

  validates :conversation_id, uniqueness: true
  validate :conversation_belongs_to_same_account

  private

  def conversation_belongs_to_same_account
    return if conversation.blank? || support_ticket.blank?
    return if conversation.account_id == support_ticket.account_id

    errors.add(:conversation_id, :invalid_account)
  end
end
