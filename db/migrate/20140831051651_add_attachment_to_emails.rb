class AddAttachmentToEmails < ActiveRecord::Migration
  def change
    add_column :emails, :attachment, :text
  end
end
