require "rails_helper"

RSpec.describe Exercise, type: :model do
  describe "バリデーション" do
    it "有効な属性なら valid" do
      expect(build(:exercise)).to be_valid
    end

    it "name が無いと invalid" do
      exercise = build(:exercise, name: nil)
      expect(exercise).to be_invalid
      expect(exercise.errors[:name]).to be_present
    end

    it "name が空白のみだと invalid" do
      exercise = build(:exercise, name: "　 ")
      expect(exercise).to be_invalid
      expect(exercise.errors[:name]).to be_present
    end

    it "同一ユーザー内で正規化後の名前が重複すると invalid" do
      user = create(:user)
      create(:exercise, user: user, name: "ベンチプレス")
      # 正規化すると同じになる表記
      exercise = build(:exercise, user: user, name: "ベンチぷれす　")
      expect(exercise).to be_invalid
      expect(exercise.errors[:name]).to be_present
    end

    it "ユーザーが異なれば同名を登録できる" do
      create(:exercise, user: create(:user), name: "ベンチプレス")
      expect(build(:exercise, user: create(:user), name: "ベンチプレス")).to be_valid
    end

    it "プリセットと同名のユーザー独自種目を登録できる" do
      create(:exercise, :preset, name: "ベンチプレス")
      expect(build(:exercise, user: create(:user), name: "ベンチプレス")).to be_valid
    end

    it "プリセット同士で正規化後の名前が重複すると invalid" do
      create(:exercise, :preset, name: "ベンチプレス")
      expect(build(:exercise, :preset, name: "ベンチぷれす")).to be_invalid
    end
  end

  describe "normalized_name の自動設定" do
    it "保存時に正規化した名前が入る" do
      exercise = create(:exercise, name: "　ベンチぷれす　")
      expect(exercise.normalized_name).to eq("ベンチプレス")
    end

    it "name を変更すると normalized_name も追従する" do
      exercise = create(:exercise, name: "スクワット")
      exercise.update!(name: "デッドリフト")
      expect(exercise.normalized_name).to eq("デッドリフト")
    end

    it "表示名は入力された表記のまま保持する" do
      exercise = create(:exercise, name: "　ベンチぷれす　")
      expect(exercise.name).to eq("　ベンチぷれす　")
    end
  end

  describe "スコープ" do
    it "preset は user_id が NULL の種目を返す" do
      preset = create(:exercise, :preset, name: "ベンチプレス")
      create(:exercise, user: create(:user), name: "マイ種目")

      expect(described_class.preset).to contain_exactly(preset)
    end

    it "owned_by は指定ユーザーの種目のみを返す" do
      user = create(:user)
      mine = create(:exercise, user: user, name: "マイ種目")
      create(:exercise, user: create(:user), name: "他人の種目")
      create(:exercise, :preset, name: "ベンチプレス")

      expect(described_class.owned_by(user)).to contain_exactly(mine)
    end

    it "available_for はプリセットと指定ユーザーの種目を返す" do
      user = create(:user)
      mine = create(:exercise, user: user, name: "マイ種目")
      preset = create(:exercise, :preset, name: "ベンチプレス")
      create(:exercise, user: create(:user), name: "他人の種目")

      expect(described_class.available_for(user)).to contain_exactly(mine, preset)
    end
  end
end
