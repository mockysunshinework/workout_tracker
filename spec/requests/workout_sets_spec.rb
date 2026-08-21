require "rails_helper"

# 5.3 記録詳細・編集画面（SPEC 4.4 画面 4）: セットの追加・修正・削除
RSpec.describe "WorkoutSets", type: :request do
  let(:user) { create(:user) }
  let(:workout) { create(:workout, user: user) }
  let(:exercise) { create(:exercise, user: user, name: "ベンチプレス") }

  before { sign_in user }

  describe "セット追加" do
    it "セットを追加すると連番が振られ、詳細画面へ戻る" do
      create(:workout_set, workout: workout, exercise: exercise, set_number: 1)

      expect {
        post workout_workout_sets_path(workout),
             params: { workout_set: { exercise_id: exercise.id, weight_kg: 60.0, reps: 10 } }
      }.to change { workout.workout_sets.count }.by(1)

      expect(response).to redirect_to(workout_path(workout))
      expect(workout.workout_sets.order(:set_number).last.set_number).to eq 2
    end

    it "プリセット種目のセットも追加できる" do
      preset = create(:exercise, :preset, name: "スクワット")

      post workout_workout_sets_path(workout),
           params: { workout_set: { exercise_id: preset.id, weight_kg: 80.0, reps: 5 } }

      expect(workout.workout_sets.count).to eq 1
    end

    it "他ユーザーの独自種目は指定できず 404 になる" do
      others_exercise = create(:exercise, name: "他人の種目")

      post workout_workout_sets_path(workout),
           params: { workout_set: { exercise_id: others_exercise.id, weight_kg: 60.0, reps: 10 } }

      expect(response).to have_http_status(:not_found)
      expect(workout.workout_sets.count).to eq 0
    end

    it "他ユーザーの workout には追加できず 404 になる" do
      others_workout = create(:workout)

      post workout_workout_sets_path(others_workout),
           params: { workout_set: { exercise_id: exercise.id, weight_kg: 60.0, reps: 10 } }

      expect(response).to have_http_status(:not_found)
    end

    it "バリデーションエラー時はセットを増やさず、エラーを通知して詳細画面へ戻る" do
      post workout_workout_sets_path(workout),
           params: { workout_set: { exercise_id: exercise.id, weight_kg: nil, reps: 10 } }

      expect(workout.workout_sets.count).to eq 0
      expect(response).to redirect_to(workout_path(workout))
      expect(flash[:alert]).to be_present
    end
  end

  describe "セット修正" do
    let!(:workout_set) do
      create(:workout_set, workout: workout, exercise: exercise,
             set_number: 1, weight_kg: 60.0, reps: 10)
    end

    it "重量と回数を修正できる" do
      patch workout_workout_set_path(workout, workout_set),
            params: { workout_set: { weight_kg: 62.5, reps: 8 } }

      expect(response).to redirect_to(workout_path(workout))

      workout_set.reload

      expect(workout_set.weight_kg).to eq BigDecimal("62.5")
      expect(workout_set.reps).to eq 8
    end

    it "set_number はパラメータに含めても変更されない（採番はシステム管理）" do
      expect {
        patch workout_workout_set_path(workout, workout_set),
              params: { workout_set: { weight_kg: 60.0, reps: 10, set_number: 99 } }
      }.not_to change { workout_set.reload.set_number }
    end

    it "他ユーザーの workout のセットは 404 になる" do
      others_set = create(:workout_set)

      expect {
        patch workout_workout_set_path(others_set.workout, others_set),
              params: { workout_set: { weight_kg: 100.0, reps: 1 } }
      }.not_to change { others_set.reload.weight_kg }

      expect(response).to have_http_status(:not_found)
    end

    it "バリデーションエラー時は値を変えず、エラーを通知する" do
      expect {
        patch workout_workout_set_path(workout, workout_set),
              params: { workout_set: { weight_kg: 60.0, reps: 0 } }
      }.not_to change { workout_set.reload.reps }

      expect(flash[:alert]).to be_present
    end
  end

  describe "セット削除" do
    it "中間セットを削除すると後続が繰り上がる（4.5 の繰り上げ）" do
      sets = (1..3).map do |n|
        create(:workout_set, workout: workout, exercise: exercise, set_number: n)
      end

      delete workout_workout_set_path(workout, sets[1])

      expect(response).to redirect_to(workout_path(workout))
      expect(workout.workout_sets.order(:set_number).pluck(:id, :set_number))
        .to eq [ [ sets[0].id, 1 ], [ sets[2].id, 2 ] ]
    end

    it "他ユーザーの workout のセットは削除できず 404 になる" do
      others_set = create(:workout_set)

      delete workout_workout_set_path(others_set.workout, others_set)

      expect(response).to have_http_status(:not_found)
      expect(WorkoutSet.exists?(others_set.id)).to be true
    end
  end
end
