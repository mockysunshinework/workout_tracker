class AddWeightKgUpperBoundToWorkoutSets < ActiveRecord::Migration[8.1]
  def change
    # 上限 1000 は実用上の決め値（SPEC 4.5）。列型 decimal(5,1) の格納上限は 9999.9 で
    # あり型では防げないため、モデルの less_than: 1000 と揃えて CHECK 制約で二層にする。
    add_check_constraint :workout_sets, "weight_kg < 1000",
                         name: "workout_sets_weight_kg_upper_bound"
  end
end
