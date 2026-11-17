require "rails_helper"

# 10.2c 種目名の別名（SPEC 4.3.1(4) / 4.5）。`ベンチ` → ベンチプレス のようにユーザーが候補選択で確定し、
# はい で confirmed になった対応を保持する。照合に使うのは confirmed の行だけ
RSpec.describe ExerciseAlias, type: :model do
  let(:user) { create(:user) }

  describe "バリデーションと正規化" do
    it "有効な factory を持つ" do
      expect(build(:exercise_alias)).to be_valid
    end

    it "alias が無いと invalid" do
      expect(build(:exercise_alias, alias: nil)).to be_invalid
      expect(build(:exercise_alias, alias: "　 ")).to be_invalid
    end

    it "保存時に normalized_alias が正規化規則（SPEC 4.3.1(1)）で自動設定され、alias は入力どおり保持される" do
      alias_record = create(:exercise_alias, user: user, alias: "　べんち　")

      expect(alias_record.normalized_alias).to eq "ベンチ"
      expect(alias_record.alias).to eq "　べんち　"
    end

    it "同一ユーザー内で正規化後の別名が重複すると invalid（表記ゆれも同一視）" do
      create(:exercise_alias, user: user, alias: "ベンチ")

      duplicate = build(:exercise_alias, user: user, alias: "べんち　")
      expect(duplicate).to be_invalid
      expect(duplicate.errors[:alias]).to be_present
    end

    it "ユーザーが異なれば同じ別名を登録できる" do
      create(:exercise_alias, user: create(:user), alias: "ベンチ")

      expect(build(:exercise_alias, user: user, alias: "ベンチ")).to be_valid
    end

    it "DB の unique index も同一ユーザー同一別名の 2 件目を拒否する（モデル検証を迂回した場合）" do
      create(:exercise_alias, user: user, alias: "ベンチ")

      # validate: false では before_validation（正規化）も走らないため、照合列を明示して unique index に当てる
      expect {
        build(:exercise_alias, user: user, alias: "ベンチ", normalized_alias: "ベンチ").save(validate: false)
      }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  describe "指せる種目（ユーザーデータの分離）" do
    it "自分の独自種目を指せる" do
      expect(build(:exercise_alias, user: user, exercise: create(:exercise, user: user))).to be_valid
    end

    it "プリセットを指せる" do
      expect(build(:exercise_alias, user: user, exercise: create(:exercise, :preset))).to be_valid
    end

    it "他ユーザーの独自種目は指せない" do
      other = build(:exercise_alias, user: user, exercise: create(:exercise, user: create(:user)))

      expect(other).to be_invalid
      expect(other.errors[:exercise]).to be_present
    end
  end

  describe "スコープ" do
    it "confirmed は確認済みの別名だけを返す" do
      confirmed = create(:exercise_alias, :confirmed, user: user)
      create(:exercise_alias, user: user)

      expect(described_class.confirmed).to contain_exactly(confirmed)
    end
  end

  # 10.6 候補選択で保存した時点で作る確認待ちの別名（SPEC 4.3.1(4)）
  describe ".propose!" do
    let(:bench) { create(:exercise, :preset, name: "ベンチプレス") }
    let(:incline) { create(:exercise, :preset, name: "インクラインベンチプレス") }

    it "確認待ち（confirmed: false）の別名行を作る" do
      alias_record = described_class.propose!(user: user, alias_name: "ベンチ", exercise: bench)

      expect(alias_record).to be_persisted
      expect(alias_record).to have_attributes(user: user, exercise: bench, alias: "ベンチ", confirmed: false)
    end

    it "同じ略称の確認待ち行があれば削除して作り直す（id 再採番で古い [はい] を無効化する）" do
      old = create(:exercise_alias, user: user, exercise: bench, alias: "べんち")

      replaced = described_class.propose!(user: user, alias_name: "ベンチ", exercise: incline)

      expect(described_class.exists?(old.id)).to be false
      expect(replaced.id).not_to eq old.id
      expect(replaced.exercise).to eq incline
      expect(user.exercise_aliases.count).to eq 1
    end

    it "同じ略称が確認済みなら何も作らず nil を返し、確認済みの行は変えない" do
      confirmed = create(:exercise_alias, :confirmed, user: user, exercise: bench, alias: "ベンチ")

      expect(described_class.propose!(user: user, alias_name: "ベンチ", exercise: incline)).to be_nil
      expect(confirmed.reload).to have_attributes(exercise: bench, confirmed: true)
      expect(user.exercise_aliases.count).to eq 1
    end

    it "他ユーザーの同じ略称には影響しない" do
      other = create(:exercise_alias, exercise: bench, alias: "ベンチ")

      described_class.propose!(user: user, alias_name: "ベンチ", exercise: bench)

      expect(described_class.exists?(other.id)).to be true
    end
  end
end
