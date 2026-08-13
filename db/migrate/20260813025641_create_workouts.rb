class CreateWorkouts < ActiveRecord::Migration[8.1]
  def change
    create_table :workouts do |t|
      # 単独の user_id index は下の複合 index が先頭列でカバーするため作らない。
      t.references :user, null: false, foreign_key: true, index: false
      t.date :performed_on, null: false
      t.text :note

      t.timestamps
    end

    # 1 ユーザー 1 日 1 レコード（SPEC 4.5）。LINE 入力は当日分に追記される。
    add_index :workouts, [ :user_id, :performed_on ], unique: true
  end
end
