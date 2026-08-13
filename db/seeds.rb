# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).

# 共通プリセット種目（SPEC 4.3.2 で確定した 22 件・6 カテゴリ）。
# 追加のみの方針（find_or_create_by!）: 再実行は既存行に触れないため常に安全。
# 一覧の修正が必要になった場合は seed の再実行ではなくマイグレーション等で明示的に行う。
preset_exercises = [
  { name: "ベンチプレス", category: "胸", bodyweight: false },
  { name: "インクラインベンチプレス", category: "胸", bodyweight: false },
  { name: "ダンベルプレス", category: "胸", bodyweight: false },
  { name: "チェストプレス", category: "胸", bodyweight: false },
  { name: "腕立て伏せ", category: "胸", bodyweight: true },
  { name: "デッドリフト", category: "背中", bodyweight: false },
  { name: "ラットプルダウン", category: "背中", bodyweight: false },
  { name: "シーテッドロー", category: "背中", bodyweight: false },
  { name: "懸垂", category: "背中", bodyweight: true },
  { name: "スクワット", category: "脚", bodyweight: false },
  { name: "ブルガリアンスクワット", category: "脚", bodyweight: true },
  { name: "レッグプレス", category: "脚", bodyweight: false },
  { name: "レッグエクステンション", category: "脚", bodyweight: false },
  { name: "レッグカール", category: "脚", bodyweight: false },
  { name: "ショルダープレス", category: "肩", bodyweight: false },
  { name: "サイドレイズ", category: "肩", bodyweight: false },
  { name: "リアレイズ", category: "肩", bodyweight: false },
  { name: "アームカール", category: "腕", bodyweight: false },
  { name: "トライセプスプレスダウン", category: "腕", bodyweight: false },
  { name: "ディップス", category: "腕", bodyweight: true },
  { name: "クランチ", category: "体幹", bodyweight: true },
  { name: "レッグレイズ", category: "体幹", bodyweight: true }
]

preset_exercises.each do |attrs|
  Exercise.preset.find_or_create_by!(name: attrs[:name]) do |exercise|
    exercise.category = attrs[:category]
    exercise.bodyweight = attrs[:bodyweight]
  end
end
