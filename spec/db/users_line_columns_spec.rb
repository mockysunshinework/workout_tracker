require "rails_helper"

# 8.5 users テーブルの再定義（SPEC 4.5・版 3.0）。DB 制約を生 SQL で直接検証する。
# factory は User モデル（8.6）の形に依存するため、ここでは使わない（3.2 / 4.1 と同方針）。
RSpec.describe "users テーブル（LINE アカウント＝ユーザー）" do
  let(:connection) { ActiveRecord::Base.connection }

  def insert_user(line_user_id:, name: "テストユーザー")
    columns = { line_user_id: line_user_id, name: name, created_at: Time.current, updated_at: Time.current }
    connection.insert(
      "INSERT INTO users (#{columns.keys.join(', ')}) VALUES (#{columns.values.map { |v| connection.quote(v) }.join(', ')})"
    )
  end

  describe "削除した列（メール＋パスワード認証・連携コードの廃止）" do
    it "email / encrypted_password / reset_password_* / line_link_code* が存在しない" do
      names = connection.columns(:users).map(&:name)

      expect(names).not_to include(
        "email", "encrypted_password", "reset_password_token", "reset_password_sent_at",
        "line_link_code", "line_link_code_expires_at"
      )
    end
  end

  describe "line_user_id" do
    it "NULL を DB が拒否する（NOT NULL）" do
      expect { insert_user(line_user_id: nil) }.to raise_error(ActiveRecord::NotNullViolation)
    end

    it "同一 line_user_id の 2 人目を DB が拒否する（unique index）" do
      insert_user(line_user_id: "U1234567890abcdef1234567890abcdef")

      expect {
        insert_user(line_user_id: "U1234567890abcdef1234567890abcdef")
      }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "unique index は部分 index ではない（NOT NULL 化に伴い WHERE 句を外す）" do
      index = connection.indexes(:users).find { |i| i.columns == [ "line_user_id" ] }

      expect(index).to be_present
      expect(index.unique).to be true
      expect(index.where).to be_nil
    end
  end

  describe "line_blocked" do
    it "既定値は false（DB default）" do
      id = insert_user(line_user_id: "Uaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")

      value = connection.select_value("SELECT line_blocked FROM users WHERE id = #{id}")
      expect(value).to be false
    end

    it "NULL を DB が拒否する" do
      id = insert_user(line_user_id: "Ubbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb")

      expect {
        connection.execute("UPDATE users SET line_blocked = NULL WHERE id = #{id}")
      }.to raise_error(ActiveRecord::NotNullViolation)
    end
  end
end
