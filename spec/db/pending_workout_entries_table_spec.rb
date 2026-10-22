require "rails_helper"

# PendingWorkoutEntry モデルは 10.5 で実装するため、ここでは DB 制約を生 SQL で直接検証する
# （exercises_table_spec / workouts_table_spec / processed_line_events_table_spec と同方針）。
# 種目確認待ちの保留入力（SPEC 4.3.1(3) / 4.5）。「1 ユーザー 1 保留」を unique index で担保する。
RSpec.describe "pending_workout_entries テーブル" do
  def insert_entry(user_id:, source_text: "ベンチ60/5", parsed_lines: '[{"line_number":1}]', expires_at: 30.minutes.from_now)
    sql = ActiveRecord::Base.sanitize_sql_array([
      "INSERT INTO pending_workout_entries (user_id, source_text, parsed_lines, expires_at, created_at, updated_at) " \
      "VALUES (?, ?, ?, ?, NOW(), NOW())",
      user_id, source_text, parsed_lines, expires_at
    ])
    ActiveRecord::Base.connection.execute(sql)
  end

  describe "[user_id] の一意制約（1 ユーザー 1 保留・SPEC 4.5）" do
    it "同一ユーザーの 2 件目の INSERT を DB が拒否する（完了条件）" do
      user = create(:user)
      insert_entry(user_id: user.id)

      expect {
        insert_entry(user_id: user.id, source_text: "スクワット80/5")
      }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "ユーザーが異なれば登録できる" do
      insert_entry(user_id: create(:user).id)

      expect {
        insert_entry(user_id: create(:user).id)
      }.not_to raise_error
    end

    it "既存行を削除すれば同一ユーザーで再登録できる（置き換えは削除＋新規作成・SPEC 4.3.1(3)）" do
      user = create(:user)
      insert_entry(user_id: user.id)
      ActiveRecord::Base.connection.execute("DELETE FROM pending_workout_entries WHERE user_id = #{user.id.to_i}")

      expect {
        insert_entry(user_id: user.id)
      }.not_to raise_error
    end
  end

  describe "カラム定義" do
    it "user_id が NULL の行を DB が拒否する" do
      expect { insert_entry(user_id: nil) }.to raise_error(ActiveRecord::NotNullViolation)
    end

    it "存在しないユーザーを指す行を DB が拒否する（FK）" do
      expect { insert_entry(user_id: 0) }.to raise_error(ActiveRecord::InvalidForeignKey)
    end

    it "source_text が NULL の行を DB が拒否する" do
      expect { insert_entry(user_id: create(:user).id, source_text: nil) }.to raise_error(ActiveRecord::NotNullViolation)
    end

    it "parsed_lines が NULL の行を DB が拒否する" do
      expect { insert_entry(user_id: create(:user).id, parsed_lines: nil) }.to raise_error(ActiveRecord::NotNullViolation)
    end

    it "parsed_lines は jsonb として保存され、JSON でない文字列は拒否する" do
      user = create(:user)
      insert_entry(user_id: user.id, parsed_lines: '[{"line_number":1,"exercise_name":"ベンチ"}]')
      stored = ActiveRecord::Base.connection.select_value(
        "SELECT parsed_lines->0->>'exercise_name' FROM pending_workout_entries WHERE user_id = #{user.id.to_i}"
      )
      expect(stored).to eq "ベンチ"

      expect { insert_entry(user_id: create(:user).id, parsed_lines: "not json") }.to raise_error(ActiveRecord::StatementInvalid)
    end

    it "expires_at が NULL の行を DB が拒否する" do
      expect { insert_entry(user_id: create(:user).id, expires_at: nil) }.to raise_error(ActiveRecord::NotNullViolation)
    end
  end
end
