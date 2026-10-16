# 種目名の別名（SPEC 4.3.1(4) / 4.5）。`ベンチ` → ベンチプレス のように、LINE の候補選択で確定した略称と
# 種目の対応をユーザーごとに保持する。候補選択で保存した時点では confirmed = false（確認待ち）で、
# エコーバック上の [はい] で true になったものだけを完全一致の照合に使う（Exercise.find_exact_match）。
class ExerciseAlias < ApplicationRecord
  belongs_to :user
  belongs_to :exercise

  scope :confirmed, -> { where(confirmed: true) }

  validates :alias, presence: true
  validates :normalized_alias, presence: true
  validate :normalized_alias_must_be_unique_for_user
  validate :exercise_must_be_available_for_user

  before_validation :assign_normalized_alias

  private

  # 表記は入力どおり保持し、照合用の名前だけを種目名と同じ規則で正規化する
  def assign_normalized_alias
    self.normalized_alias = ExerciseNameNormalizer.call(self.alias)
  end

  # 一意性は正規化名で見る（DB の unique index [user_id, normalized_alias] と二層）。
  # 利用者が入力するのは alias の方なのでエラーは :alias に付ける（Exercise の normalized_name と同じ方針）
  def normalized_alias_must_be_unique_for_user
    return if normalized_alias.blank?

    duplicates = self.class.where(user_id: user_id, normalized_alias: normalized_alias)
    duplicates = duplicates.where.not(id: id) if persisted?
    errors.add(:alias, :taken) if duplicates.exists?
  end

  # 別名が指せるのは自分の独自種目か共通プリセットだけ（CLAUDE.md ユーザーデータの分離）
  def exercise_must_be_available_for_user
    return if exercise.nil? || exercise.user_id.nil? || exercise.user_id == user_id

    errors.add(:exercise, :invalid)
  end
end
