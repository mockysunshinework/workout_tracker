class CreateExerciseAliases < ActiveRecord::Migration[8.1]
  def change
    # 種目名の別名（SPEC 4.3.1(4) / 4.5）。ユーザーが LINE の候補選択で確定した略称 → 種目の対応を保持する。
    create_table :exercise_aliases do |t|
      # 単独の user_id index は下の複合 index が先頭列でカバーするため作らない。
      t.references :user, null: false, foreign_key: true, index: false
      # 独自種目・プリセットのどちらを指してもよい。種目削除時の連鎖はモデル側（dependent: :destroy）で行う。
      t.references :exercise, null: false, foreign_key: true
      # 入力された表記（確認文・Web 表示用）と照合用の正規化名（規則は SPEC 4.3.1(1)）。
      t.string :alias, null: false
      t.string :normalized_alias, null: false
      # false = 確認待ち（照合には使わない）。はい で true、いいえ で行削除。
      t.boolean :confirmed, null: false, default: false

      t.timestamps
    end

    # 1 ユーザー内で別名は一意（SPEC 4.5）。
    add_index :exercise_aliases, [ :user_id, :normalized_alias ], unique: true
  end
end
