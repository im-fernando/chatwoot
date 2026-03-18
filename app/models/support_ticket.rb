# == Schema Information
#
# Table name: support_tickets
#
#  id            :bigint           not null, primary key
#  account_id    :bigint           not null
#  display_id    :integer          not null
#  title         :string           not null
#  description   :text
#  status        :integer          default("open"), not null
#  created_by_id :bigint           not null
#  assignee_id   :bigint
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#
class SupportTicket < ApplicationRecord
  belongs_to :account
  belongs_to :created_by, class_name: 'User'
  belongs_to :assignee, class_name: 'User', optional: true

  has_many :ticket_conversations, dependent: :destroy
  has_many :conversations, through: :ticket_conversations
  has_many :ticket_comments, dependent: :destroy

  enum status: { open: 0, pending: 1, resolved: 2 }

  validates :title, presence: true
  validates :account_id, presence: true
  validates :created_by_id, presence: true
  validate :assignee_in_account, if: -> { assignee_id.present? }

  before_create :assign_display_id

  scope :latest, -> { order(created_at: :desc) }

  private

  def assign_display_id
    return if display_id.present?

    aid = account_id.to_i
    seq = "support_ticket_dpid_seq_#{aid}"
    self.class.connection.execute("CREATE SEQUENCE IF NOT EXISTS #{seq}")
    self.display_id = self.class.connection.select_value(
      "SELECT nextval('#{seq}')"
    ).to_i
  end

  def assignee_in_account
    return if account.users.exists?(id: assignee_id)

    errors.add(:assignee_id, :invalid)
  end
end
