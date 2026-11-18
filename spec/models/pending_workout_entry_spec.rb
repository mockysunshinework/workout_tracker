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

  # 10.6 postback（候補選択・新規登録）での確定と、全行確定後の保存用データ
  describe "#resolve_current!" do
    let(:bench) { create(:exercise, :preset, name: "ベンチプレス") }

    it "確認中の未知種目の行に種目 id を入れて保存し、次の未知種目が確認対象になる" do
      entry = create(:pending_workout_entry, user: user, parsed_lines: lines)

      entry.resolve_current!(bench, chosen: true)

      entry.reload
      expect(entry.parsed_lines[1]).to include("exercise_id" => bench.id, "chosen" => true)
      expect(entry.current_unknown["exercise_name"]).to eq "DL"
    end

    it "同じ種目名（表記ゆれを含む）の未解決行はまとめて確定する" do
      same_name = lines + [ lines[1].merge("line_number" => 4, "exercise_name" => "べんち") ]
      entry = create(:pending_workout_entry, user: user, parsed_lines: same_name)

      entry.resolve_current!(bench, chosen: true)

      expect(entry.reload.parsed_lines.map { |l| l["exercise_id"] }).to eq [ 1, bench.id, nil, bench.id ]
    end

    it "新規登録での確定（chosen: false）は別名の対象にしない" do
      entry = create(:pending_workout_entry, user: user, parsed_lines: lines)

      entry.resolve_current!(bench, chosen: false)

      expect(entry.reload.parsed_lines[1]).to include("exercise_id" => bench.id, "chosen" => false)
    end
  end

  describe "#current_unknown_bodyweight?" do
    it "確認中の種目名の行に自重（重量なし）のグループがあれば true" do
      expect(build(:pending_workout_entry, parsed_lines: lines.last(1))).to be_current_unknown_bodyweight
      expect(build(:pending_workout_entry, parsed_lines: lines)).not_to be_current_unknown_bodyweight
    end
  end

  describe "#resolved_entries" do
    let(:bench) { create(:exercise, :preset, name: "ベンチプレス") }
    let(:mine) { create(:exercise, user: user, name: "DL") }
    let(:resolved_lines) do
      [ lines[0].merge("exercise_id" => bench.id), lines[1].merge("exercise_id" => bench.id), lines[2].merge("exercise_id" => mine.id) ]
    end

    it "行ごとに [種目, パース結果と同じ形の Entry] を返す（重量は BigDecimal・自重は nil）" do
      entries = build(:pending_workout_entry, user: user, parsed_lines: resolved_lines).resolved_entries

      expect(entries.map(&:first)).to eq [ bench, bench, mine ]
      expect(entries.map { |_, e| e.exercise_name }).to eq %w[ベンチプレス ベンチ DL]
      expect(entries.map { |_, e| e.groups.map { |g| [ g.weight_kg, g.reps, g.sets ] } })
        .to eq [ [ [ BigDecimal("60"), 5, 3 ] ], [ [ BigDecimal("70"), 3, 1 ] ], [ [ nil, 10, 1 ] ] ]
    end

    it "保留中に種目が削除されていた場合は nil" do
      mine.destroy!

      expect(build(:pending_workout_entry, user: user, parsed_lines: resolved_lines).resolved_entries).to be_nil
    end

    it "他ユーザーの独自種目の id が入っていても使わない（nil）" do
      others = create(:exercise, name: "他人の種目")
      tampered = [ lines[0].merge("exercise_id" => others.id) ]

      expect(build(:pending_workout_entry, user: user, parsed_lines: tampered).resolved_entries).to be_nil
    end
  end

  describe "#alias_candidates" do
    it "候補選択で確定した行の [略称, 種目 id] を、正規化後の略称で重複なく返す" do
      chosen = [
        lines[0],
        lines[1].merge("exercise_id" => 5, "chosen" => true),
        lines[1].merge("line_number" => 3, "exercise_name" => "べんち", "exercise_id" => 5, "chosen" => true),
        lines[2].merge("exercise_id" => 9, "chosen" => false)
      ]

      expect(build(:pending_workout_entry, parsed_lines: chosen).alias_candidates).to eq [ [ "ベンチ", 5 ] ]
    end
  end
end
