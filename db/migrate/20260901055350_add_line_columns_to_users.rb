class AddLineColumnsToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :line_user_id, :string
    add_column :users, :line_link_code, :string
    add_column :users, :line_link_code_expires_at, :datetime
    # unfollow（ブロック）で true、follow（再友だち追加）で false に戻す（SPEC 4.2.1）
    add_column :users, :line_blocked, :boolean, null: false, default: false

    # 連携済みユーザーのみ一意（SPEC 4.5 の指定どおり NOT NULL 行のみの部分 index。
    # 未連携＝NULL の行を index から除外する）
    add_index :users, :line_user_id, unique: true, where: "line_user_id IS NOT NULL"
    add_index :users, :line_link_code, unique: true
  end
end
