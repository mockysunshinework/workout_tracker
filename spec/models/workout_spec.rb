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
end
