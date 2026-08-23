require "rails_helper"

# 5.3 記録詳細・編集画面（SPEC 4.4 画面 4）: セット単位の表示
# 追加・修正・削除は spec/requests/workout_sets_spec.rb で検証する。
RSpec.describe "Workout detail", type: :request do
  let(:user) { create(:user) }
  let(:workout) { create(:workout, user: user, performed_on: Date.new(2026, 8, 20)) }

  before { sign_in user }

  describe "セット一覧の表示" do
    it "種目名・セット番号・重量・回数が表示される" do
      bench = create(:exercise, user: user, name: "ベンチプレス")
      create(:workout_set, workout: workout, exercise: bench,
             set_number: 1, weight_kg: 62.5, reps: 10)

      get workout_path(workout)

      cells = response.parsed_body.css("tbody tr td").map { |td| td.text.strip }
      expect(cells).to include("ベンチプレス", "1", "62.5", "10")
    end

    it "自重種目で重量未入力のセットは重量が空欄で表示される" do
      pushup = create(:exercise, user: user, name: "腕立て伏せ", bodyweight: true)
      create(:workout_set, workout: workout, exercise: pushup,
             set_number: 1, weight_kg: nil, reps: 15)

      get workout_path(workout)

      row = response.parsed_body.css("tbody tr").first.css("td").map { |td| td.text.strip }
      expect(row).to include("腕立て伏せ", "1", "", "15")
    end

    it "セットの削除ボタンに確認ダイアログ用の data-turbo-confirm が付与される" do
      bench = create(:exercise, user: user, name: "ベンチプレス")
      set = create(:workout_set, workout: workout, exercise: bench, set_number: 1, reps: 10)

      get workout_path(workout)

      # 属性が「削除ボタンに」付いていることまで固定する（行内の別要素では通らない）
      buttons = response.parsed_body.css("#workout_set_#{set.id} button[data-turbo-confirm]")
      expect(buttons.map(&:text)).to eq [ "削除" ]
    end

    it "セットは種目ごとにセット番号順で表示される" do
      bench = create(:exercise, user: user, name: "ベンチプレス")
      squat = create(:exercise, user: user, name: "スクワット")
      create(:workout_set, workout: workout, exercise: squat, set_number: 1, reps: 5)
      create(:workout_set, workout: workout, exercise: bench, set_number: 2, reps: 8)
      create(:workout_set, workout: workout, exercise: bench, set_number: 1, reps: 10)

      get workout_path(workout)

      rows = response.parsed_body.css("tbody tr").map { |tr| tr.css("td")[0..1].map { |td| td.text.strip } }
      expect(rows).to eq [
        [ "ベンチプレス", "1" ],
        [ "ベンチプレス", "2" ],
        [ "スクワット", "1" ]
      ]
    end
  end
end
