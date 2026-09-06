FactoryBot.define do
  factory :user do
    sequence(:line_user_id) { |n| "U#{n.to_s.rjust(32, '0')}" }
    name { "テストユーザー" }
  end
end
