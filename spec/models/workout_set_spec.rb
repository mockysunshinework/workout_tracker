require "rails_helper"

RSpec.describe WorkoutSet, type: :model do
  describe "factory" do
    it "有効な factory を持つ" do
      expect(build(:workout_set)).to be_valid
    end

    it "自重種目の trait も有効" do
      expect(build(:workout_set, :bodyweight)).to be_valid
    end
  end

  describe "reps の検証" do
    it "nil は無効" do
      expect(build(:workout_set, reps: nil)).to be_invalid
    end

    it "0 は無効（> 0）" do
      expect(build(:workout_set, reps: 0)).to be_invalid
    end

    it "負値は無効" do
      expect(build(:workout_set, reps: -1)).to be_invalid
    end

    it "小数は無効（整数のみ）" do
      expect(build(:workout_set, reps: 1.5)).to be_invalid
    end

    it "1 は有効（> 0 の境界値）" do
      expect(build(:workout_set, reps: 1)).to be_valid
    end
  end

  describe "set_number の検証" do
    it "nil は無効" do
      expect(build(:workout_set, set_number: nil)).to be_invalid
    end

    it "0 は無効（> 0）" do
      expect(build(:workout_set, set_number: 0)).to be_invalid
    end

    it "1 は有効（> 0 の境界値）" do
      expect(build(:workout_set, set_number: 1)).to be_valid
    end

    it "同一 workout×種目内で重複すると無効" do
      existing = create(:workout_set, set_number: 1)
      duplicate = build(:workout_set, workout: existing.workout,
                        exercise: existing.exercise, set_number: 1)

      expect(duplicate).to be_invalid
      expect(duplicate.errors[:set_number]).to be_present
    end

    it "同一 workout×種目でも set_number が異なれば有効" do
      existing = create(:workout_set, set_number: 1)
      next_set = build(:workout_set, workout: existing.workout,
                       exercise: existing.exercise, set_number: 2)

      expect(next_set).to be_valid
    end
  end

  describe "weight_kg の検証（bodyweight は「重量入力の省略を許すか」・SPEC 4.5）" do
    it "自重種目（bodyweight: true）は nil でも有効" do
      exercise = create(:exercise, bodyweight: true)

      expect(build(:workout_set, exercise: exercise, weight_kg: nil)).to be_valid
    end

    it "自重種目でも重量を入力できる（加重ディップス等）" do
      exercise = create(:exercise, bodyweight: true)

      expect(build(:workout_set, exercise: exercise, weight_kg: 10.0)).to be_valid
    end

    it "非自重種目（bodyweight: false）は nil だと無効" do
      exercise = create(:exercise, bodyweight: false)
      workout_set = build(:workout_set, exercise: exercise, weight_kg: nil)

      expect(workout_set).to be_invalid
      expect(workout_set.errors[:weight_kg]).to be_present
    end

    it "負値は無効（>= 0）" do
      expect(build(:workout_set, weight_kg: -0.5)).to be_invalid
    end

    it "0 は有効（>= 0 の境界値。自重種目の明示 0 を想定）" do
      expect(build(:workout_set, weight_kg: 0)).to be_valid
    end

    it "1000 以上は無効（decimal(5,1) の上限）" do
      expect(build(:workout_set, weight_kg: 1000)).to be_invalid
    end

    it "999.9 は有効（decimal(5,1) の上限境界値）" do
      expect(build(:workout_set, weight_kg: 999.9)).to be_valid
    end
  end
end
