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

  # 9.3 LINE 入力の種目照合 手順 1（SPEC 4.3.1(2)）: 正規化した名前の完全一致。
  # 一致しない場合の候補提案は 10 章
  describe ".find_exact_match（正規化名の完全一致・ユーザー独自 → プリセットの順）" do
    let(:user) { create(:user) }

    it "表記ゆれ（ひらがな・末尾全角空白）はプリセットに解決される" do
      preset = create(:exercise, :preset, name: "ベンチプレス")

      expect(described_class.find_exact_match(user: user, name: "ベンチぷれす")).to eq(preset)
      expect(described_class.find_exact_match(user: user, name: "ベンチプレス　")).to eq(preset)
    end

    it "ユーザー独自種目に解決される" do
      mine = create(:exercise, user: user, name: "マイ種目")

      expect(described_class.find_exact_match(user: user, name: "まい種目")).to eq(mine)
    end

    it "プリセットと同名の独自種目がある場合は独自種目を優先する" do
      create(:exercise, :preset, name: "ベンチプレス")
      mine = create(:exercise, user: user, name: "ベンチプレス")

      expect(described_class.find_exact_match(user: user, name: "ベンチプレス")).to eq(mine)
    end

    it "他ユーザーの独自種目には解決されない" do
      create(:exercise, user: create(:user), name: "他人の種目")

      expect(described_class.find_exact_match(user: user, name: "他人の種目")).to be_nil
    end

    it "前方一致・部分一致では解決されない（候補提案は別フロー）" do
      create(:exercise, :preset, name: "ベンチプレス")
      create(:exercise, :preset, name: "インクラインベンチプレス")

      expect(described_class.find_exact_match(user: user, name: "ベンチ")).to be_nil
      expect(described_class.find_exact_match(user: user, name: "インクライン")).to be_nil
    end

    it "内部の空白は区別する（`ベンチ プレス` は `ベンチプレス` と別種目）" do
      create(:exercise, :preset, name: "ベンチプレス")

      expect(described_class.find_exact_match(user: user, name: "ベンチ プレス")).to be_nil
    end

    it "空白のみの名前は nil を返す" do
      expect(described_class.find_exact_match(user: user, name: "　 ")).to be_nil
    end
  end

  # 10.2c 確認済みの別名を照合に組み込む（SPEC 4.3.1(2) 手順 1: 独自種目 → 確認済み別名 → プリセット）
  describe ".find_exact_match と別名（SPEC 4.3.1(4)）" do
    let(:user) { create(:user) }
    let!(:bench) { create(:exercise, :preset, name: "ベンチプレス") }

    it "確認済みの別名は正規化して一致し、指している種目を返す（プリセットを指す別名も可）" do
      create(:exercise_alias, :confirmed, user: user, exercise: bench, alias: "ベンチ")

      expect(described_class.find_exact_match(user: user, name: "べんち　")).to eq bench
    end

    it "未確認の別名は一致しない" do
      create(:exercise_alias, user: user, exercise: bench, alias: "ベンチ")

      expect(described_class.find_exact_match(user: user, name: "ベンチ")).to be_nil
    end

    it "他ユーザーの確認済み別名には一致しない" do
      create(:exercise_alias, :confirmed, user: create(:user), exercise: bench, alias: "ベンチ")

      expect(described_class.find_exact_match(user: user, name: "ベンチ")).to be_nil
    end

    it "別名と同じ名前の独自種目を後から作った場合は独自種目が勝つ" do
      create(:exercise_alias, :confirmed, user: user, exercise: bench, alias: "ベンチ")
      mine = create(:exercise, user: user, name: "ベンチ")

      expect(described_class.find_exact_match(user: user, name: "ベンチ")).to eq mine
    end

    it "別名はプリセットより優先される（プリセットと同じ名前の別名が別の種目を指す場合）" do
      incline = create(:exercise, :preset, name: "インクラインベンチプレス")
      create(:exercise_alias, :confirmed, user: user, exercise: incline, alias: "ベンチプレス")

      expect(described_class.find_exact_match(user: user, name: "ベンチプレス")).to eq incline
    end
  end

  # 10.4 候補検索（SPEC 4.3.1(2) 手順 2）: 完全一致しなかった入力に対し、前方一致 → 部分一致 → 類似度の順で
  # 最大 4 件。閾値 0.25 は 10.1 の決め値。同順位内は名前の短い順 → 独自種目優先 → id 順（プリセットは seed 順）
  describe ".candidates_for（候補検索）" do
    let(:user) { create(:user) }
    # 仕様書 4.3.2 の順で作る（id 順 = seed 順になる）
    let!(:presets) do
      %w[ベンチプレス インクラインベンチプレス ダンベルプレス チェストプレス 腕立て伏せ デッドリフト ラットプルダウン
         シーテッドロー 懸垂 スクワット ブルガリアンスクワット レッグプレス レッグエクステンション レッグカール
         ショルダープレス サイドレイズ リアレイズ アームカール トライセプスプレスダウン ディップス クランチ レッグレイズ]
        .map { |name| create(:exercise, :preset, name: name) }
    end

    def names_for(input)
      described_class.candidates_for(user: user, name: input).map(&:name)
    end

    it "前方一致を部分一致より先に返す（`ベンチ` → ベンチプレス、インクラインベンチプレス）" do
      expect(names_for("ベンチ")).to eq %w[ベンチプレス インクラインベンチプレス]
    end

    it "入力は正規化してから照合する（ひらがな・全角空白）" do
      expect(names_for("　べんち　")).to eq %w[ベンチプレス インクラインベンチプレス]
    end

    it "同順位内は名前の短い順、同じ長さは id 順（`レッグ` の前方一致 4 件）" do
      expect(names_for("レッグ")).to eq %w[レッグプレス レッグカール レッグレイズ レッグエクステンション]
    end

    it "最大 4 件に絞る（`プレス` は部分一致 7 件）" do
      expect(names_for("プレス")).to eq %w[ベンチプレス レッグプレス ダンベルプレス チェストプレス]
    end

    it "前方一致・部分一致が無ければ類似度 0.25 以上を高い順に返す（1 文字の誤字）" do
      expect(names_for("デットリフト")).to eq %w[デッドリフト]
      expect(names_for("ベンチプレスス")).to eq %w[ベンチプレス]
      expect(names_for("腕立てふせ")).to eq %w[腕立て伏せ]
    end

    it "前方一致・部分一致が 4 件に満たないときだけ類似度で補う（`レッグカル` は類似度のみ）" do
      expect(names_for("レッグカル").first).to eq "レッグカール"
    end

    it "どれにも当たらなければ空（`ランジ`）" do
      expect(names_for("ランジ")).to eq []
    end

    it "自分の独自種目は含み、同順位ではプリセットより先に返す。他ユーザーの種目は含まない" do
      mine = create(:exercise, user: user, name: "ベンチフライ")
      create(:exercise, user: create(:user), name: "ベンチディップ")

      expect(names_for("ベンチ")).to eq [ mine.name, "ベンチプレス", "インクラインベンチプレス" ]
    end

    it "LIKE のワイルドカード文字はそのまま文字として扱う" do
      expect(names_for("%")).to eq []
      expect(names_for("_")).to eq []
    end

    it "空白のみの入力は空" do
      expect(names_for("　 ")).to eq []
    end
  end

  describe "別名の連鎖削除（SPEC 4.5）" do
    it "別名付きの種目（記録なし）を destroy すると別名も消える" do
      exercise = create(:exercise)
      alias_record = create(:exercise_alias, user: exercise.user, exercise: exercise)

      exercise.destroy

      expect(described_class.exists?(exercise.id)).to be false
      expect(ExerciseAlias.exists?(alias_record.id)).to be false
    end

    it "使用中の種目は別名があっても従来どおり削除できず、別名も残る" do
      exercise = create(:exercise)
      create(:workout_set, exercise: exercise)
      alias_record = create(:exercise_alias, user: exercise.user, exercise: exercise)

      expect(exercise.destroy).to be false
      expect(ExerciseAlias.exists?(alias_record.id)).to be true
    end
  end

  describe "削除制限（使用中の記録がある種目は削除不可・SPEC 4.3）" do
    it "workout_sets で使用中の種目は destroy できず、レコードが残る" do
      exercise = create(:exercise)
      create(:workout_set, exercise: exercise)

      expect(exercise.destroy).to be false
      expect(exercise.errors[:base]).to be_present
      expect(described_class.exists?(exercise.id)).to be true
    end

    it "使用されていない種目は destroy できる" do
      exercise = create(:exercise)

      expect(exercise.destroy).to be_truthy
      expect(described_class.exists?(exercise.id)).to be false
    end
  end
end
