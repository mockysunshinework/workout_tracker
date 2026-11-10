# 種目確認待ちの保留入力（SPEC 4.3.1(3) / 4.5）。未知の種目を含む記録メッセージを、Quick Reply での
# 候補確認が終わるまで保持する。1 ユーザー 1 保留（unique index [user_id]）。確定・キャンセル・期限切れで物理削除する。
#
# parsed_lines（jsonb）の構造（10.5 で確定）。パース結果の行ごとに 1 要素:
#   [
#     { "line_number" => 1, "exercise_name" => "ベンチプレス", "exercise_id" => 12,
#       "groups" => [ { "weight_kg" => "60.0", "reps" => 5, "sets" => 3 } ] },
#     { "line_number" => 2, "exercise_name" => "ベンチ", "exercise_id" => nil, "groups" => [ ... ] }
#   ]
#   - exercise_id: 完全一致で解決済みなら種目 id、未知なら nil。10.6 の postback（候補選択・新規登録）で埋める
#   - weight_kg: 小数 1 桁の文字列（BigDecimal の JSON 表現）。自重は nil
#   - 先頭の exercise_id が nil の行が「いま確認中の未知種目」（current_unknown）
class PendingWorkoutEntry < ApplicationRecord
  belongs_to :user

  # 発行から 30 分（SPEC 4.3.1(3)・案）。期限切れ後の postback には再入力を案内する（10.6）
  EXPIRES_IN = 30.minutes

  validates :source_text, presence: true
  validates :parsed_lines, presence: true
  validates :expires_at, presence: true

  # 後勝ちの置き換え（SPEC 4.3.1(3)）: 既存行の物理削除 → 新規行の作成を同一トランザクションで行う。
  # UPDATE ではなく id を採番し直すことで、破棄済み保留の Quick Reply ボタン（stale postback）を無効化する。
  # 並行受信で unique 制約に当たった場合は RecordNotUnique をそのまま伝播させ、Webhook 全体を 500 →
  # LINE の再送でやり直す（SPEC 4.2.4 の一時的な障害。リトライ方式は採らない: 10.5 の決定）
  def self.replace_for!(user, source_text:, parsed_lines:)
    transaction do
      where(user: user).delete_all
      create!(user: user, source_text: source_text, parsed_lines: parsed_lines, expires_at: EXPIRES_IN.from_now)
    end
  end

  # いま候補確認の対象になっている行（未解決の先頭行）。全行解決済みなら nil
  def current_unknown
    parsed_lines.find { |line| line["exercise_id"].nil? }
  end

  def expired?
    expires_at <= Time.current
  end
end
