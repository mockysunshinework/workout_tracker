require "rails_helper"

# Workout モデルは 4.3 で実装するため、ここでは DB 制約を生 SQL で直接検証する。
RSpec.describe "workouts テーブル" do
  # optional に渡さなかった列は INSERT 文から除外する（exercises_table_spec と同方針）。
  def insert_workout(user_id:, performed_on:, **optional)
    unknown = optional.keys - %i[note]
    raise ArgumentError, "unknown column: #{unknown.join(", ")}" if unknown.any?

    values = { user_id: user_id, performed_on: performed_on, **optional }
    columns = values.keys.join(", ")
    placeholders = Array.new(values.size, "?").join(", ")

    sql = ActiveRecord::Base.sanitize_sql_array([
      "INSERT INTO workouts (#{columns}, created_at, updated_at) " \
      "VALUES (#{placeholders}, NOW(), NOW())",
      *values.values
    ])
    ActiveRecord::Base.connection.execute(sql)
  end

  describe "[user_id, performed_on] の一意制約（1 ユーザー 1 日 1 レコード）" do
    it "同一ユーザー同一日の 2 件目を DB が拒否する" do
      user = create(:user)
      insert_workout(user_id: user.id, performed_on: "2026-08-13")

      expect {
        insert_workout(user_id: user.id, performed_on: "2026-08-13")
      }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "同一ユーザーでも日付が異なれば登録できる" do
      user = create(:user)
      insert_workout(user_id: user.id, performed_on: "2026-08-13")

      expect {
        insert_workout(user_id: user.id, performed_on: "2026-08-14")
      }.not_to raise_error
    end

    it "同一日でもユーザーが異なれば登録できる" do
      user_a = create(:user)
      user_b = create(:user)
      insert_workout(user_id: user_a.id, performed_on: "2026-08-13")

      expect {
        insert_workout(user_id: user_b.id, performed_on: "2026-08-13")
      }.not_to raise_error
    end
  end

  describe "カラム定義" do
    it "user_id が NULL の行を DB が拒否する" do
      expect {
        insert_workout(user_id: nil, performed_on: "2026-08-13")
      }.to raise_error(ActiveRecord::NotNullViolation)
    end

    it "存在しない user_id の行を DB が拒否する（外部キー制約）" do
      expect {
        insert_workout(user_id: -1, performed_on: "2026-08-13")
      }.to raise_error(ActiveRecord::InvalidForeignKey)
    end

    it "performed_on が NULL の行を DB が拒否する" do
      user = create(:user)

      expect {
        insert_workout(user_id: user.id, performed_on: nil)
      }.to raise_error(ActiveRecord::NotNullViolation)
    end

    it "note は省略できる（NULL 可）" do
      user = create(:user)
      insert_workout(user_id: user.id, performed_on: "2026-08-13")

      row = ActiveRecord::Base.connection.select_one(
        "SELECT note FROM workouts WHERE user_id = #{user.id}"
      )
      expect(row["note"]).to be_nil
    end

    it "note を明示すればその値が入る" do
      user = create(:user)
      insert_workout(user_id: user.id, performed_on: "2026-08-13", note: "調子よし")

      row = ActiveRecord::Base.connection.select_one(
        "SELECT note FROM workouts WHERE user_id = #{user.id}"
      )
      expect(row["note"]).to eq("調子よし")
    end
  end
end
