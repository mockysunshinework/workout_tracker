class Exercise < ApplicationRecord
  # user_id が NULL の行は共通プリセット（SPEC 4.5）
  belongs_to :user, optional: true
  # 使用中の記録がある種目は削除不可（SPEC 4.3）。DB の FK 制約と二層で担保する。
  has_many :workout_sets, dependent: :restrict_with_error
  # 別名は種目の付属情報なので種目と一緒に消す（SPEC 4.5）。上の削除制限が先に評価されるため、
  # 使用中の種目では別名も消えない（宣言順に依存）
  has_many :exercise_aliases, dependent: :destroy

  scope :preset, -> { where(user_id: nil) }
  scope :owned_by, ->(user) { where(user: user) }
  scope :available_for, ->(user) { where(user: [ user, nil ]) }

  validates :name, presence: true
  validates :normalized_name, presence: true
  validate :normalized_name_must_be_unique_in_scope

  before_validation :assign_normalized_name

  # LINE 入力の種目照合 手順 1（SPEC 4.3.1(2)）: 正規化した名前の完全一致で、ユーザー独自種目 →
  # ユーザーの確認済み別名（SPEC 4.3.1(4)）→ 共通プリセットの順に探す。一致しなければ nil
  # （候補提案は 10 章の別フロー。ここでは推測しない）。
  # 入力名の正規化は保存時（assign_normalized_name）と同じ ExerciseNameNormalizer を使うので、
  # `ベンチぷれす` や末尾全角空白の表記ゆれは同じ normalized_name に畳まれて一致する
  def self.find_exact_match(user:, name:)
    normalized_name = ExerciseNameNormalizer.call(name)
    return nil if normalized_name.blank?

    owned_by(user).find_by(normalized_name: normalized_name) ||
      user.exercise_aliases.confirmed.find_by(normalized_alias: normalized_name)&.exercise ||
      preset.find_by(normalized_name: normalized_name)
  end

  # 候補検索の上限と類似度の閾値（SPEC 4.3.1(2)・10.1 の決め値。閾値は 10.4 のテストケースで調整する）
  MAX_CANDIDATES = 4
  SIMILARITY_THRESHOLD = 0.25

  # LINE 入力の種目照合 手順 2（SPEC 4.3.1(2)）: 完全一致しなかった入力に対する候補。
  # 利用できる種目（独自＋プリセット）を、前方一致 → 部分一致 → pg_trgm の類似度（閾値以上）の順に
  # 最大 MAX_CANDIDATES 件返す。同順位内は名前の短い順 → 独自種目 → id 順（プリセットは seed の順）。
  # 類似度は 1 文字の誤字（`デットリフト`）を拾うためのもので、略称は前方・部分一致で拾える（10.1 の実測）。
  # LIKE の % と _ はエスケープして文字として扱う。閾値はセッション設定ではなく SQL に明示する
  def self.candidates_for(user:, name:)
    query = ExerciseNameNormalizer.call(name)
    return [] if query.blank?

    like_pattern = "%#{sanitize_sql_like(query)}%"
    prefix_pattern = "#{sanitize_sql_like(query)}%"
    rank = sanitize_sql_array([
      "CASE WHEN normalized_name LIKE ? THEN 0 WHEN normalized_name LIKE ? THEN 1 ELSE 2 END",
      prefix_pattern, like_pattern
    ])
    similarity = sanitize_sql_array([ "similarity(normalized_name, ?)", query ])

    available_for(user)
      .where("normalized_name LIKE ? OR #{similarity} >= ?", like_pattern, SIMILARITY_THRESHOLD)
      .order(Arel.sql("#{rank} ASC, CASE WHEN #{rank} = 2 THEN -#{similarity} ELSE length(normalized_name) END ASC, user_id IS NULL ASC, id ASC"))
      .limit(MAX_CANDIDATES)
      .to_a
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
