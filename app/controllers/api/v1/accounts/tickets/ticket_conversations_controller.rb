class Api::V1::Accounts::Tickets::TicketConversationsController < Api::V1::Accounts::BaseController
  before_action :set_ticket
  before_action :authorize_manage!

  def index
    @links = @ticket.ticket_conversations.includes(conversation: %i[contact inbox])
  end

  def create
    conversation = find_accessible_conversation!
    if conversation.ticket_conversation.present?
      render json: { error: I18n.t('errors.support_ticket.conversation_already_linked') },
             status: :unprocessable_entity
      return
    end
    @ticket.ticket_conversations.create!(conversation: conversation)
    head :created
  end

  def destroy
    link = @ticket.ticket_conversations.joins(:conversation).find_by!(
      conversations: { display_id: params[:conversation_display_id] }
    )
    link.destroy!
    head :ok
  end

  private

  def set_ticket
    did = params[:ticket_display_id].presence || params[:display_id]
    @ticket = policy_scope(SupportTicket).find_by!(display_id: did)
  end

  def authorize_manage!
    authorize @ticket, :manage_conversations?
  end

  def find_accessible_conversation!
    display_id = create_params[:conversation_display_id]
    raise ActiveRecord::RecordNotFound if display_id.blank?

    conv = Current.account.conversations.find_by!(display_id: display_id)
    authorize conv, :show?
    conv
  end

  def create_params
    params.require(:ticket_conversation).permit(:conversation_display_id)
  end
end
