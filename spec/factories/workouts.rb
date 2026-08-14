FactoryBot.define do
  factory :workout do
    user
    # 同一ユーザー同一日は登録できないため、既定では日付をずらす
    sequence(:performed_on) { |n| Date.new(2026, 1, 1) + n }
    note { nil }
  end
end
