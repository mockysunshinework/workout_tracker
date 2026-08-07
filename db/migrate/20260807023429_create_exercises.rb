class CreateExercises < ActiveRecord::Migration[8.1]
  def change
    create_table :exercises do |t|
      # user_id が NULL の行は共通プリセット（SPEC 4.5）。
      # 単独の user_id index は下の複合 index が先頭列でカバーするため作らない。
      t.references :user, null: true, foreign_key: true, index: false
      t.string :name, null: false
      t.string :normalized_name, null: false
      t.string :category
      t.boolean :bodyweight, null: false, default: false

      t.timestamps
    end

    # PostgreSQL は既定で NULL 同士を異なる値として扱うため、そのままでは
    # プリセット（user_id が NULL）の同名が重複登録できてしまう。
    # NULLS NOT DISTINCT で NULL 同士も同値とみなす（PostgreSQL 15 以降）。
    add_index :exercises, [ :user_id, :normalized_name ],
              unique: true, nulls_not_distinct: true
  end
end
