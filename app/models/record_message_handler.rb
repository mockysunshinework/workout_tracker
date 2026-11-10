# LINE の記録メッセージを処理する（9.4・SPEC 4.2.2 / 4.2.3）:
#   パース（RecordMessageParser）→ 種目照合（Exercise.find_exact_match）→ 当日 workout への一括保存
# 呼び出し側（Webhook コントローラ）が ProcessedLineEvent.record_once のトランザクション内で呼び、
# 返信（LineMessages.recorded）はそのコミット後に行う。LINE SDK の型は受け取らない（SPEC 2.3 の境界）。
# 部分保存はしない: 1 行でも失敗（パース失敗・未知の種目・無効な値）したら何も保存しない
module RecordMessageHandler
  # 処理結果。status ごとに使うフィールドが決まる:
  #   :saved             saved（エコーバック用の保存内容）
  #   :unrecognized      記録の形（`重量/回数`）を含む行が 1 つもない「その他テキスト」（SPEC 4.2.1 → ヘルプ案内）。
  #                      旧記法 `ベンチ 60 5 3` もここ（推測補正せず形式の案内のみ・9.1）
  #   :parse_failed      parse_result（記録の形の行があって失敗。失敗行と理由を返信する・9.5）
  #   :unknown_exercises unknown_names（照合できなかった種目名。候補提案は 10 章）
  #   :invalid           invalid_messages（モデル検証のエラー。例: 重量が必要な種目に自重で入力）
  Outcome = Data.define(:status, :saved, :parse_result, :unknown_names, :invalid_messages) do
    def initialize(status:, saved: nil, parse_result: nil, unknown_names: [], invalid_messages: [])
      super
    end
  end

  # 保存内容（エコーバック用）。groups は入力どおりのグループ列（RecordMessageParser::Group）、
  # daily_set_count はその種目の当日セット数（今回分を含む・都度送信で増えていく）
  Saved = Data.define(:performed_on, :entries, :total_set_count)
  SavedEntry = Data.define(:exercise_name, :groups, :daily_set_count)

  module_function

  def call(user:, text:, performed_on:)
    parse_result = RecordMessageParser.call(text)
    unless parse_result.success?
      status = record_like?(text) ? :parse_failed : :unrecognized
      return Outcome.new(status: status, parse_result: parse_result)
    end

    resolved = parse_result.entries.map { |entry| [ Exercise.find_exact_match(user: user, name: entry.exercise_name), entry ] }
    unknown_names = resolved.filter_map { |exercise, entry| entry.exercise_name if exercise.nil? }.uniq
    return Outcome.new(status: :unknown_exercises, unknown_names: unknown_names) if unknown_names.any?

    Outcome.new(status: :saved, saved: save(user, performed_on, resolved))
  rescue ActiveRecord::RecordInvalid => e
    message = "#{e.record.try(:exercise)&.name}: #{e.record.errors.full_messages.join('、')}"
    Outcome.new(status: :invalid, invalid_messages: [ message ])
  end

  # 当日 workout の取得/作成とセットの追記を savepoint（requires_new）で囲む。無効な値で失敗したときに
  # 作りかけの workout やセットだけを巻き戻し、外側のトランザクション（冪等 ID の登録）は中断させない。
  # 同じ種目が複数行に分かれていても種目ごとにまとめる（初出の順・グループは行の順）: DB の結果は 1 行に
  # 並べた場合と同じなので、エコーバックも同じ形にする（PR #69 レビュー指摘）
  def save(user, performed_on, resolved)
    groups_by_exercise = resolved.each_with_object({}) do |(exercise, entry), acc|
      (acc[exercise] ||= []).concat(entry.groups)
    end

    Workout.transaction(requires_new: true) do
      workout = Workout.find_or_create_for_day!(user: user, performed_on: performed_on)
      groups_by_exercise.each do |exercise, groups|
        sets = groups.flat_map { |g| Array.new(g.sets) { { weight_kg: g.weight_kg, reps: g.reps } } }
        workout.append_sets!(exercise: exercise, sets: sets)
      end

      counts = workout.workout_sets.group(:exercise_id).count
      entries = groups_by_exercise.map do |exercise, groups|
        SavedEntry.new(exercise_name: exercise.name, groups: groups, daily_set_count: counts.fetch(exercise.id))
      end
      Saved.new(performed_on: performed_on, entries: entries, total_set_count: counts.values.sum)
    end
  end

  # 記録として書こうとしたテキストか（`/` を含む行が 1 つでもあれば記録の形とみなす）。
  # 「こんにちは」のような雑談と、`ベンチプレス60/` のような書き損じを返信文で区別するため
  def record_like?(text)
    text.to_s.unicode_normalize(:nfkc).include?("/")
  end

  private_class_method :save, :record_like?
end
