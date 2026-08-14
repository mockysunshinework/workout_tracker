require "rails_helper"

# WorkoutSet モデルは 4.3 で実装するため、ここでは DB 制約を生 SQL で直接検証する。
RSpec.describe "workout_sets テーブル" do
  # optional に渡さなかった列は INSERT 文から除外する（exercises_table_spec と同方針）。
  def insert_workout_set(workout_id:, exercise_id:, reps: 10, set_number: 1, **optional)
    unknown = optional.keys - %i[weight_kg]
    raise ArgumentError, "unknown column: #{unknown.join(", ")}" if unknown.any?

    values = { workout_id: workout_id, exercise_id: exercise_id,
               reps: reps, set_number: set_number, **optional }
    columns = values.keys.join(", ")
    placeholders = Array.new(values.size, "?").join(", ")

    sql = ActiveRecord::Base.sanitize_sql_array([
      "INSERT INTO workout_sets (#{columns}, created_at, updated_at) " \
      "VALUES (#{placeholders}, NOW(), NOW())",
      *values.values
    ])
    ActiveRecord::Base.connection.execute(sql)
  end

  # Workout モデルも未実装（4.3）のため、workout 行も生 SQL で用意する。
  def create_workout_row(user, performed_on: "2026-08-13")
    ActiveRecord::Base.connection.select_value(
      ActiveRecord::Base.sanitize_sql_array([
        "INSERT INTO workouts (user_id, performed_on, created_at, updated_at) " \
        "VALUES (?, ?, NOW(), NOW()) RETURNING id",
        user.id, performed_on
      ])
    )
  end

  let(:user) { create(:user) }
  let(:workout_id) { create_workout_row(user) }
  let(:exercise) { create(:exercise, user: user) }

  describe "[workout_id, exercise_id, set_number] の一意制約" do
    it "同一 workout×種目×set_number の重複を DB が拒否する" do
      insert_workout_set(workout_id: workout_id, exercise_id: exercise.id, set_number: 1)

      expect {
        insert_workout_set(workout_id: workout_id, exercise_id: exercise.id, set_number: 1)
      }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "同一 workout×種目でも set_number が異なれば登録できる" do
      insert_workout_set(workout_id: workout_id, exercise_id: exercise.id, set_number: 1)

      expect {
        insert_workout_set(workout_id: workout_id, exercise_id: exercise.id, set_number: 2)
      }.not_to raise_error
    end

    it "同一 workout×set_number でも種目が異なれば登録できる" do
      other_exercise = create(:exercise, user: user)
      insert_workout_set(workout_id: workout_id, exercise_id: exercise.id, set_number: 1)

      expect {
        insert_workout_set(workout_id: workout_id, exercise_id: other_exercise.id, set_number: 1)
      }.not_to raise_error
    end
  end

  describe "カラム定義" do
    # 制約違反はトランザクションを中断させるため、1 example につき違反は 1 回に留める
    # （2 回目以降の SQL が InFailedSqlTransaction になる）。
    it "workout_id が NULL の行を DB が拒否する" do
      expect {
        insert_workout_set(workout_id: nil, exercise_id: exercise.id)
      }.to raise_error(ActiveRecord::NotNullViolation)
    end

    it "exercise_id が NULL の行を DB が拒否する" do
      expect {
        insert_workout_set(workout_id: workout_id, exercise_id: nil)
      }.to raise_error(ActiveRecord::NotNullViolation)
    end

    it "reps が NULL の行を DB が拒否する" do
      expect {
        insert_workout_set(workout_id: workout_id, exercise_id: exercise.id, reps: nil)
      }.to raise_error(ActiveRecord::NotNullViolation)
    end

    it "set_number が NULL の行を DB が拒否する" do
      expect {
        insert_workout_set(workout_id: workout_id, exercise_id: exercise.id, set_number: nil)
      }.to raise_error(ActiveRecord::NotNullViolation)
    end

    it "存在しない workout_id の行を DB が拒否する（外部キー制約）" do
      expect {
        insert_workout_set(workout_id: -1, exercise_id: exercise.id)
      }.to raise_error(ActiveRecord::InvalidForeignKey)
    end

    it "存在しない exercise_id の行を DB が拒否する（外部キー制約）" do
      expect {
        insert_workout_set(workout_id: workout_id, exercise_id: -1)
      }.to raise_error(ActiveRecord::InvalidForeignKey)
    end

    it "weight_kg は省略できる（自重種目は NULL）" do
      insert_workout_set(workout_id: workout_id, exercise_id: exercise.id)

      row = ActiveRecord::Base.connection.select_one(
        "SELECT weight_kg FROM workout_sets WHERE workout_id = #{workout_id}"
      )
      expect(row["weight_kg"]).to be_nil
    end

    it "weight_kg は decimal(5,1) として値を保持する" do
      insert_workout_set(workout_id: workout_id, exercise_id: exercise.id, weight_kg: 102.5)

      row = ActiveRecord::Base.connection.select_one(
        "SELECT weight_kg FROM workout_sets WHERE workout_id = #{workout_id}"
      )
      expect(row["weight_kg"]).to eq(BigDecimal("102.5"))
    end
  end

  describe "数値の範囲（CHECK 制約）" do
    it "weight_kg の負値を DB が拒否する" do
      expect {
        insert_workout_set(workout_id: workout_id, exercise_id: exercise.id, weight_kg: -0.5)
      }.to raise_error(ActiveRecord::StatementInvalid, /weight_kg/)
    end

    it "weight_kg の 0 は登録できる（>= 0 の境界値）" do
      expect {
        insert_workout_set(workout_id: workout_id, exercise_id: exercise.id, weight_kg: 0)
      }.not_to raise_error
    end

    it "weight_kg の 1000 以上を DB が拒否する（上限は実用上の決め値・SPEC 4.5）" do
      expect {
        insert_workout_set(workout_id: workout_id, exercise_id: exercise.id, weight_kg: 1000)
      }.to raise_error(ActiveRecord::StatementInvalid, /weight_kg/)
    end

    it "weight_kg の 999.9 は登録できる（< 1000 の境界値）" do
      expect {
        insert_workout_set(workout_id: workout_id, exercise_id: exercise.id, weight_kg: 999.9)
      }.not_to raise_error
    end

    it "reps の 0 以下を DB が拒否する" do
      expect {
        insert_workout_set(workout_id: workout_id, exercise_id: exercise.id, reps: 0)
      }.to raise_error(ActiveRecord::StatementInvalid, /reps/)
    end

    it "set_number の 0 以下を DB が拒否する" do
      expect {
        insert_workout_set(workout_id: workout_id, exercise_id: exercise.id, set_number: 0)
      }.to raise_error(ActiveRecord::StatementInvalid, /set_number/)
    end
  end
end
