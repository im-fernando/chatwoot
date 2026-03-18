class AddWhatsappMenuTriageEnabledToInboxes < ActiveRecord::Migration[7.1]
  def change
    add_column :inboxes, :whatsapp_menu_triage_enabled, :boolean, default: false, null: false
  end
end
