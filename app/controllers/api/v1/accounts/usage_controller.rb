class Api::V1::Accounts::UsageController < Api::V1::Accounts::BaseController
  before_action :check_authorization

  def show
    render json: { usage: Current.account.resource_usage }
  end

  private

  def check_authorization
    raise Pundit::NotAuthorizedError unless Current.account_user&.administrator?
  end
end
