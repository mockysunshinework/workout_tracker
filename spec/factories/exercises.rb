FactoryBot.define do
  factory :exercise do
    user
    sequence(:name) { |n| "マイ種目#{n}" }
    category { "胸" }
    bodyweight { false }

    # user_id が NULL の行は共通プリセット（SPEC 4.5）
    trait :preset do
      user { nil }
    end
  end
end
