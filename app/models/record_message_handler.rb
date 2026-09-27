# LINE の記録メッセージを処理する（9.4・SPEC 4.2.2 / 4.2.3）:
#   パース（RecordMessageParser）→ 種目照合（Exercise.find_exact_match）→ 当日 workout への一括保存
# 呼び出し側（Webhook コントローラ）が ProcessedLineEvent.record_once のトランザクション内で呼び、
# 返信（LineMessages.recorded）はそのコミット後に行う。LINE SDK の型は受け取らない（SPEC 2.3 の境界）。
# 部分保存はしない: 1 行でも失敗（パース失敗・未知の種目・無効な値）したら何も保存しない
module RecordMessageHandler
  # 処理結果。status ごとに使うフィールドが決まる:
  #   :saved             saved（エコーバック用の保存内容）
  #   :parse_failed      parse_result（失敗行と理由。返信は 9.5）
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
    return Outcome.new(status: :parse_failed, parse_result: parse_result) unless parse_result.success?

    resolved = parse_result.entries.map { |entry| [ Exercise.find_exact_match(user: user, name: entry.exercise_name), entry ] }
    unknown_names = resolved.filter_map { |exercise, entry| entry.exercise_name if exercise.nil? }.uniq
    return Outcome.new(status: :unknown_exercises, unknown_names: unknown_names) if unknown_names.any?

    Outcome.new(status: :saved, saved: save(user, performed_on, resolved))
  rescue ActiveRecord::RecordInvalid => e
    message = "#{e.record.try(:exercise)&.name}: #{e.record.errors.full_messages.join('、')}"
    Outcome.new(status: :invalid, invalid_messages: [ message ])
  end

  # 当日 workout の取得/作成とセットの追記を savepoint（requires_new）で囲む。無効な値で失敗したときに
  # 作りかけの workout やセットだけを巻き戻し、外側のトランザクション（冪等 ID の登録）は中断させない
  def save(user, performed_on, resolved)
    Workout.transaction(requires_new: true) do
      workout = Workout.find_or_create_for_day!(user: user, performed_on: performed_on)
      resolved.each do |exercise, entry|
        sets = entry.groups.flat_map { |g| Array.new(g.sets) { { weight_kg: g.weight_kg, reps: g.reps } } }
        workout.append_sets!(exercise: exercise, sets: sets)
      end

      counts = workout.workout_sets.group(:exercise_id).count
      entries = resolved.map do |exercise, entry|
        SavedEntry.new(exercise_name: exercise.name, groups: entry.groups, daily_set_count: counts.fetch(exercise.id))
      end
      Saved.new(performed_on: performed_on, entries: entries, total_set_count: counts.values.sum)
    end
  end

  private_class_method :save
end
