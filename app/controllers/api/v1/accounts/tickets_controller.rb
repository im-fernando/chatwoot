class Api::V1::Accounts::TicketsController < Api::V1::Accounts::BaseController
  before_action :authorize_index, only: [:index]
  before_action :authorize_create, only: [:create]
  before_action :set_ticket, only: [:show, :update, :destroy]

  def index
    @tickets = policy_scope(SupportTicket).includes(:created_by, :assignee).latest
    if params[:status].present? && SupportTicket.statuses.key?(params[:status])
      @tickets = @tickets.where(status: params[:status])
    end
    @tickets = @tickets.page(params[:page]).per(25)
    @tickets_count = @tickets.total_count
  end

  def show
    @ticket = ticket_with_includes(@ticket.id)
  end

  def create
    conv = conversation_for_ticket_link
    if conv == :already_linked
      render json: { error: I18n.t('errors.support_ticket.conversation_already_linked') },
             status: :unprocessable_entity
      return
    end

    attrs = ticket_params.except(:conversation_display_id).merge(created_by: Current.user)
    record = Current.account.support_tickets.create!(attrs)
    record.ticket_conversations.create!(conversation: conv) if conv
    @ticket = ticket_with_includes(record.id)
    render :show, status: :created
  end

  def update
    @ticket.update!(ticket_params)
    @ticket = ticket_with_includes(@ticket.id)
    render :show
  end

  def destroy
    @ticket.destroy!
    head :ok
  end

  private

  def authorize_index
    authorize SupportTicket
  end

  def authorize_create
    authorize SupportTicket
  end

  def set_ticket
    @ticket = policy_scope(SupportTicket).find_by!(display_id: params[:display_id])
    authorize @ticket
  end

  def ticket_with_includes(id)
    policy_scope(SupportTicket).includes(
      :created_by, :assignee,
      ticket_comments: [:user],
      ticket_conversations: { conversation: %i[contact inbox] }
    ).find(id)
  end

  def ticket_params
    params.require(:ticket).permit(:title, :description, :status, :assignee_id, :conversation_display_id)
  end

  # Returns Conversation, nil, or :already_linked
  def conversation_for_ticket_link
    display_id = ticket_params[:conversation_display_id]
    return nil if display_id.blank?

    conv = Current.account.conversations.find_by!(display_id: display_id)
    authorize conv, :show?
    return :already_linked if conv.ticket_conversation.present?

    conv
  end
end
