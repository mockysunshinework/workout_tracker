FactoryBot.define do
  factory :workout_set do
    workout
    exercise
    weight_kg { 60.0 }
    reps { 10 }
    set_number { 1 }

    # 自重種目のセット（weight_kg は省略可能）
    trait :bodyweight do
      association :exercise, :preset, bodyweight: true
      weight_kg { nil }
    end
  end
end
