require "rails_helper"

# 6.3 ダッシュボード（SPEC 4.4 画面 2）: 当週サマリと、グラフ描画用の HTML 契約を検証する。
# グラフ描画自体は Chart.js のクライアント挙動のためブラウザで手動確認する（plan.md 6.3）。
RSpec.describe "Dashboard", type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  describe "当週サマリ" do
    # 値は data-summary フックで取得し、文言・レイアウト変更でロジック検証が壊れないようにする
    def summary_value(key)
      response.parsed_body.css("#weekly-summary [data-summary='#{key}']").text.strip
    end

    it "当週（月曜起点）の実施日数と総セット数を表示する" do
      monday = Date.current.beginning_of_week
      exercise = create(:exercise, user: user)
      workout1 = create(:workout, user: user, performed_on: monday)
      # Date.current だと月曜日に実行したとき workout1 と同日になり一意制約に当たるため、
      # どの曜日でも「週内かつ別日」になる月曜+1日を使う
      workout2 = create(:workout, user: user, performed_on: monday + 1)
      create(:workout_set, workout: workout1, exercise: exercise, set_number: 1)
      create(:workout_set, workout: workout1, exercise: exercise, set_number: 2)
      create(:workout_set, workout: workout2, exercise: exercise, set_number: 1)

      get root_path

      expect(summary_value(:days)).to eq "2"
      expect(summary_value(:sets)).to eq "3"
    end

    it "サマリの項目名（実施日数・総セット数）が表示される（仕様書 4.4 の表示項目）" do
      get root_path

      text = response.parsed_body.css("#weekly-summary").text
      expect(text).to include("実施日数", "総セット数")
    end

    it "先週以前の記録はサマリに含めない" do
      exercise = create(:exercise, user: user)
      last_week = create(:workout, user: user,
                         performed_on: Date.current.beginning_of_week - 1)
      create(:workout_set, workout: last_week, exercise: exercise, set_number: 1)

      get root_path

      expect(summary_value(:days)).to eq "0"
      expect(summary_value(:sets)).to eq "0"
    end

    it "他ユーザーの当週の記録はサマリに含めない" do
      other_user = create(:user)
      others = create(:workout, user: other_user, performed_on: Date.current)
      create(:workout_set, workout: others,
             exercise: create(:exercise, user: other_user), set_number: 1)

      get root_path

      expect(summary_value(:days)).to eq "0"
    end
  end

  describe "グラフの HTML 契約（描画は手動確認）" do
    it "種目別推移グラフの要素と種目セレクト・期間切替がある" do
      create(:exercise, user: user, name: "ベンチプレス")

      get root_path

      doc = response.parsed_body
      progress = doc.css("[data-controller='progress-chart']")
      expect(progress).to be_present
      expect(progress.css("canvas")).to be_present
      select = progress.css("select[data-progress-chart-target='exerciseSelect'] option")
      expect(select.map(&:text)).to include("ベンチプレス")
      months = progress.css("select[data-progress-chart-target='monthsSelect'] option")
      expect(months.map { |o| o["value"] }).to eq %w[1 3 6]
    end

    it "月間頻度グラフの要素がある" do
      get root_path

      frequency = response.parsed_body.css("[data-controller='frequency-chart']")
      expect(frequency).to be_present
      expect(frequency.css("canvas")).to be_present
    end

    it "種目セレクトにはプリセットと自分の種目が入り、他ユーザーの種目は入らない" do
      create(:exercise, user: user, name: "マイ種目")
      create(:exercise, :preset, name: "スクワット")
      create(:exercise, name: "他人の種目")

      get root_path

      options = response.parsed_body
        .css("select[data-progress-chart-target='exerciseSelect'] option").map(&:text)
      expect(options).to include("マイ種目", "スクワット")
      expect(options).not_to include("他人の種目")
    end
  end
end
