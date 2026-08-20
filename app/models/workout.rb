class Workout < ApplicationRecord
  belongs_to :user
  # 記録は物理削除（SPEC 4.3）。workout 削除時は配下のセットも削除する。
  has_many :workout_sets, dependent: :destroy

  # 一意性は 1 ユーザー 1 日 1 レコード（SPEC 4.5）。DB の unique index と二層で担保する。
  validates :performed_on, presence: true, uniqueness: { scope: :user_id }

  # 一覧表示用の集計（SPEC 4.4 画面 3: 種目数・総セット数）。行ごとの追加クエリを避ける。
  scope :with_set_stats, -> {
    left_joins(:workout_sets)
      .select("workouts.*",
              "COUNT(DISTINCT workout_sets.exercise_id) AS exercise_count",
              "COUNT(workout_sets.id) AS total_set_count")
      .group(:id)
  }
  scope :performed_in, ->(month) { where(performed_on: month.all_month) }

  # 同一 workout×種目の最大 set_number の次を振って追記する（SPEC 4.5。例: 1,2,3 の後は 4,5）。
  # 並行入力（LINE と Web 等）とは workout 行の SELECT FOR UPDATE で直列化する
  # （2026-08-14 決定。制約違反リトライ方式は中断トランザクションの回復が複雑なため不採用）。
  def append_set(exercise:, **attributes)
    with_lock do
      next_number = workout_sets.where(exercise: exercise).maximum(:set_number).to_i + 1
      # 自動採番を後置し、attributes に set_number が紛れても上書きされないようにする
      workout_sets.create(**attributes, exercise: exercise, set_number: next_number)
    end
  end

  # セット削除時に同一 workout×種目の後続セットを繰り上げ、歯抜けを作らない（SPEC 4.5）。
  # 削除と繰り上げは同一トランザクションで行い、採番（append_set）と同じ行ロックで直列化する。
  # 繰り上げは小さい番号から順に更新するため、空いた枠に詰める形になり一意制約と衝突しない。
  def remove_set(workout_set)
    unless workout_set.workout_id == id
      raise ArgumentError, "workout_set does not belong to this workout"
    end

    with_lock do
      workout_set.destroy!
      followers = workout_sets.where(exercise_id: workout_set.exercise_id)
                              .where(set_number: (workout_set.set_number + 1)..)
                              .order(:set_number)
      followers.each { |set| set.update!(set_number: set.set_number - 1) }
      workout_set
    end
  end
end
