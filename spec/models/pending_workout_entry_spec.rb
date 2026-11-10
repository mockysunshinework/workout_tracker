require "rails_helper"

# 10.5 種目確認待ちの保留入力（SPEC 4.3.1(3) / 4.5）。1 ユーザー 1 保留で、置き換えは削除＋新規作成（id 再採番）
RSpec.describe PendingWorkoutEntry, type: :model do
  let(:user) { create(:user) }
  let(:lines) do
    [
      { "line_number" => 1, "exercise_name" => "ベンチプレス", "exercise_id" => 1, "groups" => [ { "weight_kg" => "60.0", "reps" => 5, "sets" => 3 } ] },
      { "line_number" => 2, "exercise_name" => "ベンチ", "exercise_id" => nil, "groups" => [ { "weight_kg" => "70.0", "reps" => 3, "sets" => 1 } ] },
      { "line_number" => 3, "exercise_name" => "DL", "exercise_id" => nil, "groups" => [ { "weight_kg" => nil, "reps" => 10, "sets" => 1 } ] }
    ]
  end

  describe "バリデーション" do
    it "有効な factory を持つ" do
      expect(build(:pending_workout_entry)).to be_valid
    end

    it "source_text / parsed_lines / expires_at が無いと invalid" do
      expect(build(:pending_workout_entry, source_text: nil)).to be_invalid
      expect(build(:pending_workout_entry, parsed_lines: nil)).to be_invalid
      expect(build(:pending_workout_entry, expires_at: nil)).to be_invalid
    end
  end

  describe ".replace_for!（後勝ちの置き換え・SPEC 4.3.1(3)）" do
    it "保留が無ければ作成し、有効期限は 30 分後になる" do
      freeze_time do
        entry = described_class.replace_for!(user, source_text: "ベンチ60/5", parsed_lines: lines)

        expect(entry).to be_persisted
        expect(entry.expires_at).to eq 30.minutes.from_now
        expect(entry.parsed_lines).to eq lines
      end
    end

    it "既存の保留は物理削除し、新しい id で作り直す（古い postback を無効化する）" do
      old = described_class.replace_for!(user, source_text: "ベンチ60/5", parsed_lines: lines)

      replaced = described_class.replace_for!(user, source_text: "スクワ80/5", parsed_lines: lines)

      expect(described_class.where(user: user).count).to eq 1
      expect(replaced.id).not_to eq old.id
      expect(described_class.exists?(old.id)).to be false
      expect(replaced.source_text).to eq "スクワ80/5"
    end

    it "他ユーザーの保留には影響しない" do
      other = create(:pending_workout_entry)

      described_class.replace_for!(user, source_text: "ベンチ60/5", parsed_lines: lines)

      expect(described_class.exists?(other.id)).to be true
    end
  end

  describe "#current_unknown" do
    it "exercise_id が未解決の最初の行を返す" do
      entry = build(:pending_workout_entry, parsed_lines: lines)

      expect(entry.current_unknown["line_number"]).to eq 2
      expect(entry.current_unknown["exercise_name"]).to eq "ベンチ"
    end

    it "全行解決済みなら nil" do
      resolved = lines.map { |l| l.merge("exercise_id" => 1) }

      expect(build(:pending_workout_entry, parsed_lines: resolved).current_unknown).to be_nil
    end
  end

  describe "#expired?" do
    it "expires_at を過ぎていれば true" do
      expect(build(:pending_workout_entry, expires_at: 1.minute.ago)).to be_expired
      expect(build(:pending_workout_entry, expires_at: 1.minute.from_now)).not_to be_expired
    end
  end
end
