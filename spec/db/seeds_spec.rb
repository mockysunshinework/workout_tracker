require "rails_helper"

RSpec.describe "db/seeds.rb" do
  # SPEC 4.3.2 の確定一覧（22 件・6 カテゴリ）。seed の内容がこの一覧から
  # ずれた場合に検知できるよう、期待値として全件を明示する。
  EXPECTED_PRESETS = [
    [ "ベンチプレス", "胸", false ],
    [ "インクラインベンチプレス", "胸", false ],
    [ "ダンベルプレス", "胸", false ],
    [ "チェストプレス", "胸", false ],
    [ "腕立て伏せ", "胸", true ],
    [ "デッドリフト", "背中", false ],
    [ "ラットプルダウン", "背中", false ],
    [ "シーテッドロー", "背中", false ],
    [ "懸垂", "背中", true ],
    [ "スクワット", "脚", false ],
    [ "ブルガリアンスクワット", "脚", true ],
    [ "レッグプレス", "脚", false ],
    [ "レッグエクステンション", "脚", false ],
    [ "レッグカール", "脚", false ],
    [ "ショルダープレス", "肩", false ],
    [ "サイドレイズ", "肩", false ],
    [ "リアレイズ", "肩", false ],
    [ "アームカール", "腕", false ],
    [ "トライセプスプレスダウン", "腕", false ],
    [ "ディップス", "腕", true ],
    [ "クランチ", "体幹", true ],
    [ "レッグレイズ", "体幹", true ]
  ].freeze

  def load_seeds
    Rails.application.load_seed
  end

  it "共通プリセット 22 件を仕様の一覧どおりに投入する" do
    load_seeds

    presets = Exercise.preset.pluck(:name, :category, :bodyweight)
    expect(presets).to match_array(EXPECTED_PRESETS)
  end

  it "再実行しても重複しない（冪等）" do
    load_seeds

    expect { load_seeds }.not_to change(Exercise.preset, :count)
  end

  it "既存のユーザー独自種目には影響しない" do
    owned = create(:exercise, name: "ベンチプレス")

    load_seeds

    expect(owned.reload.user).to be_present
    expect(Exercise.preset.count).to eq EXPECTED_PRESETS.size
  end
end
