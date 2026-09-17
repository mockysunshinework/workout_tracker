class Exercise < ApplicationRecord
  # user_id が NULL の行は共通プリセット（SPEC 4.5）
  belongs_to :user, optional: true
  # 使用中の記録がある種目は削除不可（SPEC 4.3）。DB の FK 制約と二層で担保する。
  has_many :workout_sets, dependent: :restrict_with_error

  scope :preset, -> { where(user_id: nil) }
  scope :owned_by, ->(user) { where(user: user) }
  scope :available_for, ->(user) { where(user: [ user, nil ]) }

  validates :name, presence: true
  validates :normalized_name, presence: true
  validate :normalized_name_must_be_unique_in_scope

  before_validation :assign_normalized_name

  # LINE 入力の種目照合 手順 1（SPEC 4.3.1(2)）: 正規化した名前の完全一致で、ユーザー独自種目 →
  # 共通プリセットの順に探す。一致しなければ nil（候補提案は 10 章の別フロー。ここでは推測しない）。
  # 入力名の正規化は保存時（assign_normalized_name）と同じ ExerciseNameNormalizer を使うので、
  # `ベンチぷれす` や末尾全角空白の表記ゆれは同じ normalized_name に畳まれて一致する
  def self.find_exact_match(user:, name:)
    normalized_name = ExerciseNameNormalizer.call(name)
    return nil if normalized_name.blank?

    owned_by(user).find_by(normalized_name: normalized_name) || preset.find_by(normalized_name: normalized_name)
  end

  private

  # 表示名は入力された表記のまま保持し、照合用の名前だけを正規化する（SPEC 4.5）
  def assign_normalized_name
    self.normalized_name = ExerciseNameNormalizer.call(name)
  end

  # 照合は normalized_name の完全一致で行うため、一意性もそちらで見る（SPEC 4.3.1）。
  # DB 側は [user_id, normalized_name] の unique index（NULLS NOT DISTINCT）で担保済み。
  # ここでの検証は入力時にエラーを返すためのもので、利用者が入力するのは name の方なので
  # エラーは :name に付ける（normalized_name は内部用の列で画面に出ない）。
  def normalized_name_must_be_unique_in_scope
    return if normalized_name.blank?

    duplicates = self.class.where(user_id: user_id, normalized_name: normalized_name)
    duplicates = duplicates.where.not(id: id) if persisted?
    errors.add(:name, :taken) if duplicates.exists?
  end
end
