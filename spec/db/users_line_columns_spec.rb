require "rails_helper"

# 8.1 users への LINE 関連カラム追加（SPEC 4.5）。DB 制約を直接検証する。
# 既存カラムの NOT NULL は factory では通せないため、行の用意は factory、
# LINE 列の書き込みはバリデーションを介さない update_column で行う。
RSpec.describe "users テーブルの LINE 関連カラム" do
  describe "line_user_id の一意制約（NOT NULL 行のみの部分 index）" do
    it "同一 line_user_id の 2 人目を DB が拒否する" do
      create(:user).update_column(:line_user_id, "U1234567890abcdef1234567890abcdef")

      expect {
        create(:user).update_column(:line_user_id, "U1234567890abcdef1234567890abcdef")
      }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "line_user_id が NULL（未連携）のユーザーは複数共存できる" do
      expect {
        create(:user)
        create(:user)
      }.not_to raise_error
    end
  end

  describe "line_link_code の一意制約" do
    it "同一 line_link_code の 2 人目を DB が拒否する" do
      create(:user).update_column(:line_link_code, "ABC123")

      expect {
        create(:user).update_column(:line_link_code, "ABC123")
      }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  describe "line_blocked" do
    it "既定値は false（DB default）" do
      user = create(:user)

      value = ActiveRecord::Base.connection.select_value(
        "SELECT line_blocked FROM users WHERE id = #{user.id}"
      )
      expect(value).to be false
    end

    it "NULL を DB が拒否する" do
      user = create(:user)

      expect {
        user.update_column(:line_blocked, nil)
      }.to raise_error(ActiveRecord::NotNullViolation)
    end
  end
end
