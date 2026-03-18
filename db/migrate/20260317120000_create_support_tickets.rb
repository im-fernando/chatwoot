class CreateSupportTickets < ActiveRecord::Migration[7.1]
  def up
    create_table :support_tickets do |t|
      t.references :account, null: false, foreign_key: true
      t.integer :display_id, null: false
      t.string :title, null: false
      t.text :description
      t.integer :status, null: false, default: 0
      t.references :created_by, null: false, foreign_key: { to_table: :users }
      t.references :assignee, null: true, foreign_key: { to_table: :users }
      t.timestamps
    end
    add_index :support_tickets, %i[account_id display_id], unique: true
    add_index :support_tickets, :status
    add_index :support_tickets, :created_at

    create_table :ticket_conversations do |t|
      t.references :support_ticket, null: false, foreign_key: true
      t.references :conversation, null: false, foreign_key: true, index: { unique: true }
      t.timestamps
    end

    create_table :ticket_comments do |t|
      t.references :support_ticket, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.text :content, null: false
      t.timestamps
    end

    Account.pluck(:id).each do |account_id|
      execute "CREATE SEQUENCE IF NOT EXISTS support_ticket_dpid_seq_#{account_id}"
    end
  end

  def down
    Account.pluck(:id).each do |account_id|
      execute "DROP SEQUENCE IF EXISTS support_ticket_dpid_seq_#{account_id}"
    end
    drop_table :ticket_comments
    drop_table :ticket_conversations
    drop_table :support_tickets
  end
end
