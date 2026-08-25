require "rails_helper"

# 6.1 種目別推移の集計（SPEC 4.4）: 日付ごとの最大重量と推定 1RM（Epley 式 weight × (1 + reps/30)）
RSpec.describe ExerciseProgress do
  let(:user) { create(:user) }
  let(:exercise) { create(:exercise, user: user, name: "ベンチプレス") }

  def add_set(date, weight, reps)
    workout = Workout.find_or_create_by!(user: user, performed_on: date)
    create(:workout_set, workout: workout, exercise: exercise,
           weight_kg: weight, reps: reps,
           set_number: workout.workout_sets.where(exercise: exercise).count + 1)
  end

  describe ".series" do
    it "日付ごとに最大重量と推定 1RM（セットごとの e1RM の最大）を日付昇順で返す" do
      # 8/1: 最大重量のセット（102.5×3 → e1RM 112.75）と、e1RM 最大のセット（100×10 → 133.33...）が異なる
      add_set(Date.new(2026, 8, 1), 100, 10)
      add_set(Date.new(2026, 8, 1), 102.5, 3)
      add_set(Date.new(2026, 8, 5), 90, 12)

      series = described_class.series(user: user, exercise: exercise, since: Date.new(2026, 8, 1))

      expect(series).to eq [
        { date: Date.new(2026, 8, 1), max_weight: 102.5, estimated_one_rm: 133.3 },
        { date: Date.new(2026, 8, 5), max_weight: 90.0, estimated_one_rm: 126.0 }
      ]
    end

    it "since より前の記録は含めない" do
      add_set(Date.new(2026, 7, 31), 100, 5)
      add_set(Date.new(2026, 8, 1), 80, 5)

      series = described_class.series(user: user, exercise: exercise, since: Date.new(2026, 8, 1))

      expect(series.map { |row| row[:date] }).to eq [ Date.new(2026, 8, 1) ]
    end

    it "他ユーザー・他種目の記録は含めない" do
      other_user = create(:user)
      other_workout = create(:workout, user: other_user, performed_on: Date.new(2026, 8, 1))
      create(:workout_set, workout: other_workout, exercise: create(:exercise, user: other_user),
             weight_kg: 200, reps: 1, set_number: 1)
      my_workout = Workout.find_or_create_by!(user: user, performed_on: Date.new(2026, 8, 1))
      create(:workout_set, workout: my_workout, exercise: create(:exercise, user: user, name: "スクワット"),
             weight_kg: 150, reps: 1, set_number: 1)
      add_set(Date.new(2026, 8, 1), 60, 10)

      series = described_class.series(user: user, exercise: exercise, since: Date.new(2026, 8, 1))

      expect(series).to eq [
        { date: Date.new(2026, 8, 1), max_weight: 60.0, estimated_one_rm: 80.0 }
      ]
    end

    it "重量未入力（自重）のセットは集計対象外" do
      bodyweight_exercise = create(:exercise, user: user, name: "腕立て伏せ", bodyweight: true)
      workout = create(:workout, user: user, performed_on: Date.new(2026, 8, 1))
      create(:workout_set, workout: workout, exercise: bodyweight_exercise,
             weight_kg: nil, reps: 15, set_number: 1)

      series = described_class.series(user: user, exercise: bodyweight_exercise,
                                      since: Date.new(2026, 8, 1))

      expect(series).to be_empty
    end

    it "記録がなければ空配列を返す" do
      series = described_class.series(user: user, exercise: exercise, since: Date.new(2026, 8, 1))

      expect(series).to eq []
    end
  end
end
