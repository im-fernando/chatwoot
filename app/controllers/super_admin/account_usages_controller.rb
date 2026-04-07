class SuperAdmin::AccountUsagesController < SuperAdmin::ApplicationController
  include ActionView::Helpers::NumberHelper

  def index
    @accounts = Account.order(id: :desc).page(params[:page]).per(25)
    @usage_data = build_usage_data(@accounts)
  end

  def show
    @account = Account.find(params[:id])
    @usage = @account.resource_usage
  end

  private

  def build_usage_data(accounts)
    account_ids = accounts.map(&:id)
    {
      agents: AccountUser.where(account_id: account_ids, role: :agent).group(:account_id).count,
      inboxes: Inbox.where(account_id: account_ids).group(:account_id).count,
      contacts: Contact.where(account_id: account_ids).group(:account_id).count,
      conversations: Conversation.where(account_id: account_ids).group(:account_id).count,
      storage: Attachment.where(account_id: account_ids)
                         .joins(file_attachment: :blob)
                         .group(:account_id)
                         .sum('active_storage_blobs.byte_size')
    }
  end
end
