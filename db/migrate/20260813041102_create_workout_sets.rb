class CreateWorkoutSets < ActiveRecord::Migration[8.1]
  def change
    create_table :workout_sets do |t|
      # 単独の workout_id index は下の複合 index が先頭列でカバーするため作らない。
      t.references :workout, null: false, foreign_key: true, index: false
      # exercise_id の単独 index はグラフ集計の結合キーとして必要（SPEC 4.5）。
      t.references :exercise, null: false, foreign_key: true
      # NULL は自重種目で重量入力を省略した場合（SPEC 4.5）。
      t.decimal :weight_kg, precision: 5, scale: 1
      t.integer :reps, null: false
      t.integer :set_number, null: false

      t.timestamps

      t.check_constraint "weight_kg >= 0", name: "workout_sets_weight_kg_non_negative"
      t.check_constraint "reps > 0", name: "workout_sets_reps_positive"
      t.check_constraint "set_number > 0", name: "workout_sets_set_number_positive"
    end

    # 同一 workout×種目内の set_number 連番の重複を DB レベルで担保（SPEC 4.5）。
    # 既定の生成名は 63 バイト制限で切り詰められてハッシュ付きになるため明示する。
    add_index :workout_sets, [ :workout_id, :exercise_id, :set_number ],
              unique: true, name: "index_workout_sets_on_workout_and_exercise_and_set_number"
  end
end
