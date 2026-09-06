require "rails_helper"

RSpec.describe User, type: :model do
  describe "バリデーション" do
    it "有効な属性なら valid" do
      expect(build(:user)).to be_valid
    end

    it "name が無いと invalid" do
      user = build(:user, name: nil)
      expect(user).to be_invalid
      expect(user.errors[:name]).to be_present
    end

    it "email が重複すると invalid" do
      create(:user, email: "dup@example.com")
      user = build(:user, email: "dup@example.com")
      expect(user).to be_invalid
      expect(user.errors[:email]).to be_present
    end
  end
end
