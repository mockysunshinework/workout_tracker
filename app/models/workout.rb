class Workout < ApplicationRecord
  belongs_to :user
  # 記録は物理削除（SPEC 4.3）。workout 削除時は配下のセットも削除する。
  has_many :workout_sets, dependent: :destroy

  # 一意性は 1 ユーザー 1 日 1 レコード（SPEC 4.5）。DB の unique index と二層で担保する。
  validates :performed_on, presence: true, uniqueness: { scope: :user_id }
end
