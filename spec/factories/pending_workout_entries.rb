FactoryBot.define do
  # 種目確認待ちの保留入力（SPEC 4.3.1(3) / 4.5）。既定は 1 行目が未知種目
  factory :pending_workout_entry do
    user
    source_text { "ベンチ60/5" }
    parsed_lines do
      [ { "line_number" => 1, "exercise_name" => "ベンチ", "exercise_id" => nil,
          "groups" => [ { "weight_kg" => "60.0", "reps" => 5, "sets" => 1 } ] } ]
    end
    expires_at { 30.minutes.from_now }
  end
end
