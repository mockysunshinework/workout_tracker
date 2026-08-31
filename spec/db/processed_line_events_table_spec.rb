require "rails_helper"

# ProcessedLineEvent モデルは 7.5b で実装するため、ここでは DB 制約を生 SQL で直接検証する
# （exercises_table_spec / workouts_table_spec と同方針）。
RSpec.describe "processed_line_events テーブル" do
  def insert_event(webhook_event_id:, received_at: Time.current)
    sql = ActiveRecord::Base.sanitize_sql_array([
      "INSERT INTO processed_line_events (webhook_event_id, received_at, created_at, updated_at) " \
      "VALUES (?, ?, NOW(), NOW())",
      webhook_event_id, received_at
    ])
    ActiveRecord::Base.connection.execute(sql)
  end

  describe "webhook_event_id の一意制約（SPEC 4.2.4 の重複排除の土台）" do
    it "同一 webhook_event_id の 2 件目を DB が拒否する" do
      insert_event(webhook_event_id: "01FZ74A0TDDPYRVKNK77XKC3ZR")

      expect {
        insert_event(webhook_event_id: "01FZ74A0TDDPYRVKNK77XKC3ZR")
      }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "webhook_event_id が異なれば登録できる" do
      insert_event(webhook_event_id: "01FZ74A0TDDPYRVKNK77XKC3ZR")

      expect {
        insert_event(webhook_event_id: "01FZ74A0TDDPYRVKNK77XKC3ZS")
      }.not_to raise_error
    end
  end

  describe "カラム定義" do
    it "webhook_event_id が NULL の行を DB が拒否する" do
      expect {
        insert_event(webhook_event_id: nil)
      }.to raise_error(ActiveRecord::NotNullViolation)
    end

    it "received_at が NULL の行を DB が拒否する" do
      expect {
        insert_event(webhook_event_id: "01FZ74A0TDDPYRVKNK77XKC3ZR", received_at: nil)
      }.to raise_error(ActiveRecord::NotNullViolation)
    end
  end
end
