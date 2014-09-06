class AddAttachmentIdToEmail < ActiveRecord::Migration
  def change
    add_column :emails, :attachment_id, :integer

  end
end
