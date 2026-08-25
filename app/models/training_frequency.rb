# 月間頻度グラフの集計（SPEC 4.4）。週または月ごとのトレーニング実施日数を返す。
# workouts は 1 ユーザー 1 日 1 レコード（SPEC 4.5）のため、行数 = 実施日数。
# 週の起点は date_trunc('week') の仕様どおり月曜（ISO 週）。
module TrainingFrequency
  module_function

  # unit ごとの固定 SQL。動的な文字列組み立てをしないことで不正値の混入を構造的に防ぐ。
  PERIOD_EXPRESSIONS = {
    week: Arel.sql("date_trunc('week', performed_on)"),
    month: Arel.sql("date_trunc('month', performed_on)")
  }.freeze

  def counts(user:, unit:, since:)
    period = PERIOD_EXPRESSIONS[unit.to_sym]
    raise ArgumentError, "unit must be one of #{PERIOD_EXPRESSIONS.keys.join(', ')}" if period.nil?

    rows = user.workouts
      .where(performed_on: since..)
      .group(period)
      .order(period)
      .count

    rows.map { |period_start, days| { period_start: period_start.to_date, days: days } }
  end
end
