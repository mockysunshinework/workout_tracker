class Workout < ApplicationRecord
  belongs_to :user
  # 記録は物理削除（SPEC 4.3）。workout 削除時は配下のセットも削除する。
  has_many :workout_sets, dependent: :destroy

  # 一意性は 1 ユーザー 1 日 1 レコード（SPEC 4.5）。DB の unique index と二層で担保する。
  validates :performed_on, presence: true, uniqueness: { scope: :user_id }

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
end
