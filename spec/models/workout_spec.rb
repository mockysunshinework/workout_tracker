require "rails_helper"

RSpec.describe Workout, type: :model do
  describe "factory" do
    it "有効な factory を持つ" do
      expect(build(:workout)).to be_valid
    end
  end

  describe "performed_on の検証" do
    it "performed_on がないと無効" do
      workout = build(:workout, performed_on: nil)

      expect(workout).to be_invalid
      expect(workout.errors[:performed_on]).to be_present
    end

    it "同一ユーザー同一日の 2 件目は無効（1 ユーザー 1 日 1 レコード）" do
      user = create(:user)
      create(:workout, user: user, performed_on: Date.new(2026, 8, 13))
      duplicate = build(:workout, user: user, performed_on: Date.new(2026, 8, 13))

      expect(duplicate).to be_invalid
      expect(duplicate.errors[:performed_on]).to be_present
    end

    it "同一日でもユーザーが異なれば有効" do
      create(:workout, performed_on: Date.new(2026, 8, 13))
      other = build(:workout, performed_on: Date.new(2026, 8, 13))

      expect(other).to be_valid
    end

    it "同一ユーザーでも日付が異なれば有効" do
      user = create(:user)
      create(:workout, user: user, performed_on: Date.new(2026, 8, 13))
      next_day = build(:workout, user: user, performed_on: Date.new(2026, 8, 14))

      expect(next_day).to be_valid
    end
  end

  describe "note" do
    it "note は省略できる" do
      expect(build(:workout, note: nil)).to be_valid
    end
  end

  describe "関連" do
    it "user から workouts を辿れる" do
      workout = create(:workout)

      expect(workout.user.workouts).to contain_exactly(workout)
    end
  end

  describe "#append_set（セット採番・SPEC 4.5）" do
    let(:user) { create(:user) }
    let(:workout) { create(:workout, user: user) }
    let(:exercise) { create(:exercise, user: user) }

    it "最初のセットは set_number 1 で追記される" do
      set = workout.append_set(exercise: exercise, reps: 10, weight_kg: 60.0)

      expect(set).to be_persisted
      expect(set.set_number).to eq 1
    end

    it "既存 1,2,3 の後の追記は 4,5 になる（仕様書 4.5 の例）" do
      (1..3).each do |n|
        create(:workout_set, workout: workout, exercise: exercise, set_number: n)
      end

      first = workout.append_set(exercise: exercise, reps: 10, weight_kg: 60.0)
      second = workout.append_set(exercise: exercise, reps: 8, weight_kg: 60.0)

      expect([ first.set_number, second.set_number ]).to eq [ 4, 5 ]
    end

    it "採番は種目ごとに独立する" do
      other_exercise = create(:exercise, user: user)
      create(:workout_set, workout: workout, exercise: exercise, set_number: 1)

      set = workout.append_set(exercise: other_exercise, reps: 10, weight_kg: 40.0)

      expect(set.set_number).to eq 1
    end

    it "採番は workout ごとに独立する" do
      other_workout = create(:workout, user: user)
      create(:workout_set, workout: other_workout, exercise: exercise, set_number: 3)

      set = workout.append_set(exercise: exercise, reps: 10, weight_kg: 60.0)

      expect(set.set_number).to eq 1
    end

    it "歯抜けがある場合も「最大の次」を振る（1,3 の次は 4）" do
      create(:workout_set, workout: workout, exercise: exercise, set_number: 1)
      create(:workout_set, workout: workout, exercise: exercise, set_number: 3)

      set = workout.append_set(exercise: exercise, reps: 10, weight_kg: 60.0)

      expect(set.set_number).to eq 4
    end

    it "attributes で set_number を渡しても自動採番が優先される" do
      create(:workout_set, workout: workout, exercise: exercise, set_number: 1)

      set = workout.append_set(exercise: exercise, reps: 10, weight_kg: 60.0, set_number: 99)

      expect(set.set_number).to eq 2
    end

    it "バリデーションエラー時は保存せず、エラー付きのレコードを返す" do
      barbell = create(:exercise, user: user, bodyweight: false)

      set = workout.append_set(exercise: barbell, reps: 10, weight_kg: nil)

      expect(set).not_to be_persisted
      expect(set.errors[:weight_kg]).to be_present
      expect(workout.workout_sets.count).to eq 0
    end
  end
end
