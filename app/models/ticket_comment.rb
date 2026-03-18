# == Schema Information
#
# Table name: ticket_comments
#
#  id                :bigint           not null, primary key
#  support_ticket_id :bigint           not null
#  user_id           :bigint           not null
#  content           :text             not null
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#
class TicketComment < ApplicationRecord
  belongs_to :support_ticket
  belongs_to :user

  validates :content, presence: true

  scope :chronological, -> { order(created_at: :asc) }
end
