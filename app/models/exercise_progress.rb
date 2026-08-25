# 種目別推移グラフの集計（SPEC 4.4）。
# 日付ごとに「最大重量」と「推定 1RM（Epley 式: weight × (1 + reps/30)）」を返す。
# 推定 1RM は各セットの e1RM の日次最大であり、最大重量セットの e1RM とは限らない
# （例: 100kg×10 の e1RM 133.3 は 102.5kg×3 の 112.8 より大きい）。
# 重量未入力（自重）のセットは重量軸のグラフに乗せられないため対象外。
module ExerciseProgress
  module_function

  def series(user:, exercise:, since:)
    rows = WorkoutSet
      .joins(:workout)
      .where(workouts: { user_id: user.id, performed_on: since.. }, exercise_id: exercise.id)
      .where.not(weight_kg: nil)
      .group("workouts.performed_on")
      .order("workouts.performed_on")
      .pluck(
        Arel.sql("workouts.performed_on"),
        Arel.sql("MAX(weight_kg)"),
        Arel.sql("MAX(weight_kg * (1 + reps / 30.0))")
      )

    rows.map do |date, max_weight, estimated_one_rm|
      {
        date: date,
        max_weight: max_weight.to_f,
        estimated_one_rm: estimated_one_rm.to_f.round(1)
      }
    end
  end
end
