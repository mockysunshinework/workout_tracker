FactoryBot.define do
  # 種目名の別名（SPEC 4.3.1(4) / 4.5）。既定は確認待ち（confirmed: false）
  factory :exercise_alias do
    user
    exercise { association :exercise, user: user }
    sequence(:alias) { |n| "べつめい#{n}" }
    confirmed { false }

    trait :confirmed do
      confirmed { true }
    end
  end
end
