require "rails_helper"

# 行ロックによる採番の直列化（4.4 で決定）を、実際に 2 接続で並行実行して検証する。
# トランザクショナルテストではテスト内のデータが他接続から見えないため、
# このファイルに限り実コミットで検証し、後始末を自前で行う。
RSpec.describe "Workout#append_set の並行実行", type: :model do
  self.use_transactional_tests = false

  after do
    WorkoutSet.delete_all
    Workout.delete_all
    Exercise.delete_all
    User.delete_all
  end

  it "同時に追記しても set_number が重複せず連番になる" do
    user = create(:user)
    workout = create(:workout, user: user)
    exercise = create(:exercise, user: user)

    ready = Queue.new
    start = Queue.new
    threads = Array.new(2) do
      Thread.new do
        target = Workout.find(workout.id)
        ready << true
        start.pop
        target.append_set(exercise: exercise, reps: 10, weight_kg: 60.0)
      end
    end

    2.times { ready.pop }
    2.times { start << true }
    results = threads.map(&:value)

    expect(results).to all(be_persisted)
    expect(workout.workout_sets.order(:set_number).pluck(:set_number)).to eq [ 1, 2 ]
  end
end
