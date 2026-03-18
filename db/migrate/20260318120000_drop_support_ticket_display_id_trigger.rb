class DropSupportTicketDisplayIdTrigger < ActiveRecord::Migration[7.1]
  def up
    execute 'DROP TRIGGER IF EXISTS support_tickets_before_insert_row_tr ON support_tickets'
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
