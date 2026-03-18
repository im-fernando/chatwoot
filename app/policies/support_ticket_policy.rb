class SupportTicketPolicy < ApplicationPolicy
  def index?
    agent_or_admin?
  end

  def show?
    agent_or_admin?
  end

  def create?
    agent_or_admin?
  end

  def update?
    agent_or_admin?
  end

  def destroy?
    agent_or_admin?
  end

  def manage_conversations?
    agent_or_admin?
  end

  def manage_comments?
    agent_or_admin?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      scope.where(account_id: account.id)
    end
  end

  private

  def agent_or_admin?
    account_user&.administrator? || account_user&.agent?
  end
end
