class AddIdAndSendingServiceToEmails < ActiveRecord::Migration
  def change
    add_column :emails, :message_id, :string
    add_column :emails, :sending_service, :string
  end
end
