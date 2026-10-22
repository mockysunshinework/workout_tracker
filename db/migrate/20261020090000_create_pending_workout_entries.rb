class CreatePendingWorkoutEntries < ActiveRecord::Migration[8.1]
  def change
    # 種目確認待ちの保留入力（SPEC 4.3.1(3) / 4.5）。未知の種目を含む記録メッセージを、
    # Quick Reply での候補確認が終わるまで保持する。確定・キャンセル・期限切れ後は物理削除する。
    create_table :pending_workout_entries do |t|
      # 「1 ユーザー 1 保留」は下の unique index で担保する。単独 index は不要（unique index が兼ねる）。
      t.references :user, null: false, foreign_key: true, index: false
      # 受信メッセージ原文（再パース・返信文に使う）
      t.text :source_text, null: false
      # パース済みの行と種目解決の進捗。内部構造は 10.5 で確定する
      t.jsonb :parsed_lines, null: false
      # 発行から 30 分（SPEC 4.3.1(3)・案）。期限切れ後の postback には再入力を案内する
      t.datetime :expires_at, null: false

      t.timestamps
    end

    # 置き換えは削除＋新規作成（id 再採番）で行い、stale postback を無効化する（SPEC 4.3.1(3)）。
    add_index :pending_workout_entries, :user_id, unique: true
  end
end
