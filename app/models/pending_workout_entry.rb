# 種目確認待ちの保留入力（SPEC 4.3.1(3) / 4.5）。未知の種目を含む記録メッセージを、Quick Reply での
# 候補確認が終わるまで保持する。1 ユーザー 1 保留（unique index [user_id]）。確定・キャンセル・期限切れで物理削除する。
#
# parsed_lines（jsonb）の構造（10.5 で確定）。パース結果の行ごとに 1 要素:
#   [
#     { "line_number" => 1, "exercise_name" => "ベンチプレス", "exercise_id" => 12,
#       "groups" => [ { "weight_kg" => "60.0", "reps" => 5, "sets" => 3 } ] },
#     { "line_number" => 2, "exercise_name" => "ベンチ", "exercise_id" => nil, "groups" => [ ... ] }
#   ]
#   - exercise_id: 完全一致で解決済みなら種目 id、未知なら nil。postback の候補選択で埋める（10.6）
#   - chosen: postback で確定した行にだけ付く。true = 候補から選んだ（別名確認の対象）、
#     false = 新規登録すると決めた（種目は全件確定時に作るので、それまで exercise_id は nil のまま・10.7）
#   - exercise_id が nil で chosen も無い先頭の行が「いま確認中の未知種目」（current_unknown）
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

  # いま候補確認の対象になっている行（未確定の先頭行）。全行確定済みなら nil
  def current_unknown
    parsed_lines.find { |line| unresolved?(line) }
  end

  def expired?
    expires_at <= Time.current
  end

  # 確認中の未知種目を、候補から選んだ exercise で確定する（SPEC 4.3.1(2) 手順 5）。同じ種目名（正規化して比較）の
  # 未確定行はまとめて確定する（同じ名前を 2 回聞かない）
  def resolve_current!(exercise)
    mark_current!("exercise_id" => exercise.id, "chosen" => true)
  end

  # 確認中の未知種目を「新規種目として登録する」と確定する。種目はここでは作らず、全件確定時に
  # create_new_exercises! で作る（途中でキャンセル・期限切れになっても何も残さないため: SPEC 4.3.1(3)）
  def resolve_current_as_new!
    mark_current!("chosen" => false)
  end

  # 新規登録すると決めた種目名ごとに独自種目を作り、行に種目 id を入れる（全件確定後・保存の直前に呼ぶ）。
  # 名前は最初に出てきた行の入力どおり。自重（重量なし）のグループが 1 つでもあれば重量を省略できる種目として作る
  # （重量必須で作ると、いま保存しようとしている自重の記録が検証エラーになるため）
  def create_new_exercises!
    new_lines = parsed_lines.select { |line| line["chosen"] == false && line["exercise_id"].nil? }
    ids_by_name = new_lines.group_by { |line| normalized_name(line) }.transform_values do |lines|
      bodyweight = lines.any? { |line| line["groups"].any? { |group| group["weight_kg"].nil? } }
      user.exercises.create!(name: lines.first["exercise_name"], bodyweight: bodyweight).id
    end

    lines = parsed_lines.map do |line|
      new_lines.include?(line) ? line.merge("exercise_id" => ids_by_name.fetch(normalized_name(line))) : line
    end
    update!(parsed_lines: lines)
  end

  # 同じ内容のまま id だけを振り直す（削除 → 新規作成）。順次確認で次の未知種目へ進むときに呼び、前の確認の
  # Quick Reply ボタンを無効にする: postback の data は pending_id と exercise_id だけなので、id が同じままだと
  # 前の種目の候補ボタンが今の種目に適用されてしまう。受付時刻（記録日の基準）と期限は引き継ぐ
  def reissue!
    transaction do
      attributes_to_keep = attributes.except("id")
      delete
      self.class.create!(attributes_to_keep)
    end
  end

  # 全行確定後の保存用データ: 行ごとの [種目, RecordMessageParser::Entry]（RecordMessageHandler.save の入力と同じ形）。
  # 種目はこのユーザーが使えるもの（独自＋プリセット）からだけ引く。保留中に種目が削除されたなどで
  # 引けない行があれば nil（呼び出し側は無効な保留として扱う）
  def resolved_entries
    exercises = Exercise.available_for(user).where(id: parsed_lines.map { |line| line["exercise_id"] }).index_by(&:id)
    return nil unless parsed_lines.all? { |line| exercises.key?(line["exercise_id"]) }

    parsed_lines.map do |line|
      groups = line["groups"].map do |group|
        RecordMessageParser::Group.new(weight_kg: group["weight_kg"]&.to_d, reps: group["reps"], sets: group["sets"])
      end
      entry = RecordMessageParser::Entry.new(line_number: line["line_number"], exercise_name: line["exercise_name"], groups: groups)
      [ exercises.fetch(line["exercise_id"]), entry ]
    end
  end

  # 別名確認の対象: 候補から選んで確定した行の [略称（入力どおり）, 種目 id]。正規化後の略称で重複を除く
  def alias_candidates
    parsed_lines.select { |line| line["chosen"] }
                .uniq { |line| normalized_name(line) }
                .map { |line| [ line["exercise_name"], line["exercise_id"] ] }
  end

  private

  def unresolved?(line)
    line["exercise_id"].nil? && !line.key?("chosen")
  end

  def normalized_name(line)
    ExerciseNameNormalizer.call(line["exercise_name"])
  end

  # 確認中の種目名と同じ名前の未確定行すべてに attributes を付けて保存する
  def mark_current!(attributes)
    name = normalized_name(current_unknown)
    lines = parsed_lines.map do |line|
      unresolved?(line) && normalized_name(line) == name ? line.merge(attributes) : line
    end
    update!(parsed_lines: lines)
  end
end
