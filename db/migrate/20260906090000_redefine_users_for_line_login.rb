# SPEC 4.5 (v3.0): the account identity is the LINE account itself. Drop the
# email/password and link-code columns (web auth moved to LINE Login) and make
# line_user_id mandatory with a plain unique index instead of the partial one.
class RedefineUsersForLineLogin < ActiveRecord::Migration[8.1]
  def change
    remove_index :users, :email, unique: true
    remove_index :users, :reset_password_token, unique: true
    remove_index :users, :line_link_code, unique: true
    remove_index :users, :line_user_id, unique: true, where: "line_user_id IS NOT NULL"

    remove_column :users, :email, :string, default: "", null: false
    remove_column :users, :encrypted_password, :string, default: "", null: false
    remove_column :users, :reset_password_token, :string
    remove_column :users, :reset_password_sent_at, :datetime
    remove_column :users, :line_link_code, :string
    remove_column :users, :line_link_code_expires_at, :datetime

    change_column_null :users, :line_user_id, false
    add_index :users, :line_user_id, unique: true
  end
end
