require "rails_helper"

# 9.4 記録メッセージの処理: パース（9.2）→ 種目照合（9.3）→ 当日 workout への一括保存（SPEC 4.2.2 / 4.2.3）。
# 返信文の組み立ては LineMessages、Reply の送信はコントローラ（コミット後）の責務
RSpec.describe RecordMessageHandler, type: :model do
  let(:user) { create(:user) }
  let(:day) { Date.new(2026, 9, 18) }
  let!(:bench) { create(:exercise, :preset, name: "ベンチプレス") }
  let!(:chinup) { create(:exercise, :preset, name: "懸垂", bodyweight: true) }

  def handle(text)
    described_class.call(user: user, text: text, performed_on: day)
  end

  def sets_of(exercise)
    user.workouts.find_by!(performed_on: day).workout_sets.where(exercise: exercise).order(:set_number)
                 .map { |s| [ s.set_number, s.weight_kg, s.reps ] }
  end

  describe "保存成功（:saved）" do
    it "複数行・複数グループ・自重を当日 workout に展開して保存し、保存内容と当日合計を返す" do
      outcome = handle("ベンチプレス60/5/2 65/5\n懸垂/10/3")

      expect(outcome.status).to eq :saved
      expect(sets_of(bench)).to eq [ [ 1, 60, 5 ], [ 2, 60, 5 ], [ 3, 65, 5 ] ]
      expect(sets_of(chinup)).to eq [ [ 1, nil, 10 ], [ 2, nil, 10 ], [ 3, nil, 10 ] ]

      saved = outcome.saved
      expect(saved.performed_on).to eq day
      expect(saved.entries.map(&:exercise_name)).to eq [ "ベンチプレス", "懸垂" ]
      expect(saved.entries.first.groups.map { |g| [ g.weight_kg, g.reps, g.sets ] }).to eq [ [ 60, 5, 2 ], [ 65, 5, 1 ] ]
      expect(saved.entries.map(&:daily_set_count)).to eq [ 3, 3 ]
      expect(saved.total_set_count).to eq 6
    end

    it "同日に既存のセットがあれば採番を続け、当日合計にも含める（都度送信）" do
      workout = create(:workout, user: user, performed_on: day)
      (1..3).each { |n| create(:workout_set, workout: workout, exercise: bench, set_number: n, weight_kg: 60, reps: 5) }

      outcome = handle("ベンチプレス70/3")

      expect(outcome.status).to eq :saved
      expect(sets_of(bench).map(&:first)).to eq [ 1, 2, 3, 4 ]
      expect(outcome.saved.entries.first.daily_set_count).to eq 4
      expect(outcome.saved.total_set_count).to eq 4
      expect(user.workouts.count).to eq 1
    end

    # PR #69 レビュー指摘: 同じ種目を複数行に分けて書いても DB の結果は 1 行に並べた場合と同じなので、
    # エコーバックも種目単位にまとめる（行単位だと種目名が重複し、当日セット数が各行に付いて読みにくい）
    it "同じ種目を複数行に分けて書いた場合は、保存内容を種目ごとに初出の位置へまとめる" do
      outcome = handle("ベンチプレス60/5\n懸垂/10/2\nベンチプレス70/3")

      expect(outcome.status).to eq :saved
      expect(sets_of(bench)).to eq [ [ 1, 60, 5 ], [ 2, 70, 3 ] ]
      expect(outcome.saved.entries.map(&:exercise_name)).to eq [ "ベンチプレス", "懸垂" ]
      expect(outcome.saved.entries.first.groups.map { |g| [ g.weight_kg, g.reps, g.sets ] }).to eq [ [ 60, 5, 1 ], [ 70, 3, 1 ] ]
      expect(outcome.saved.entries.map(&:daily_set_count)).to eq [ 2, 2 ]
      expect(outcome.saved.total_set_count).to eq 4
    end

    it "表記ゆれの種目名は照合で解決され、保存内容には種目の正式な表示名が入る" do
      outcome = handle("べんちぷれす60/5")

      expect(outcome.status).to eq :saved
      expect(outcome.saved.entries.first.exercise_name).to eq "ベンチプレス"
    end

    it "同名ならユーザー独自種目を優先して紐付ける" do
      mine = create(:exercise, user: user, name: "ベンチプレス")

      handle("ベンチプレス60/5")

      expect(sets_of(mine).size).to eq 1
      expect(WorkoutSet.where(exercise: bench)).to be_empty
    end
  end

  describe "保存しないケース（部分保存しない・SPEC 4.2.3）" do
    it "パース失敗は :parse_failed を返し、何も保存しない" do
      outcome = handle("ベンチプレス 60 5 3")

      expect(outcome.status).to eq :parse_failed
      expect(outcome.parse_result.errors.map(&:reason)).to eq [ :missing_group ]
      expect(Workout.count).to eq 0
    end

    it "未知の種目を含む場合は :unknown_exercises を返し、既知の行も含めて何も保存しない" do
      outcome = handle("ベンチプレス60/5\nベンチ60/5\nDL100/5\nベンチ70/3")

      expect(outcome.status).to eq :unknown_exercises
      expect(outcome.unknown_names).to eq [ "ベンチ", "DL" ]
      expect(Workout.count).to eq 0
    end

    it "重量が必要な種目に自重で入力した場合は :invalid を返し、当日 workout も含めて何も残さない" do
      outcome = handle("懸垂/10\nベンチプレス/10/3")

      expect(outcome.status).to eq :invalid
      expect(outcome.invalid_messages.join).to include("ベンチプレス")
      expect(Workout.count).to eq 0
      expect(WorkoutSet.count).to eq 0
    end

    it "無効入力でも呼び出し側のトランザクション（冪等 ID の登録）は中断しない" do # 筋トレ記録の保存に失敗しても、LINEイベント自体は“処理済み”として記録する ということ
      registered = ProcessedLineEvent.record_once("01EVENT0000000000000000001") do
        handle("ベンチプレス/10/3")
      end

      expect(registered).to be true
      expect(ProcessedLineEvent.count).to eq 1
    end
  end
end
