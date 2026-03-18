class Api::V1::Accounts::Tickets::CommentsController < Api::V1::Accounts::BaseController
  before_action :set_ticket
  before_action :authorize_comments!

  def index
    @comments = @ticket.ticket_comments.includes(:user).chronological
  end

  def create
    @comment = @ticket.ticket_comments.create!(comment_params.merge(user: Current.user))
    render :create, status: :created
  end

  private

  def set_ticket
    did = params[:ticket_display_id].presence || params[:display_id]
    @ticket = policy_scope(SupportTicket).find_by!(display_id: did)
  end

  def authorize_comments!
    authorize @ticket, :manage_comments?
  end

  def comment_params
    params.require(:ticket_comment).permit(:content)
  end
end
