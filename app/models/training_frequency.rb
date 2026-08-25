# 月間頻度グラフの集計（SPEC 4.4）。週または月ごとのトレーニング実施日数を返す。
# workouts は 1 ユーザー 1 日 1 レコード（SPEC 4.5）のため、行数 = 実施日数。
# 週の起点は date_trunc('week') の仕様どおり月曜（ISO 週）。
module TrainingFrequency
  module_function

  UNITS = %w[week month].freeze

  def counts(user:, unit:, since:)
    unless UNITS.include?(unit.to_s)
      raise ArgumentError, "unit must be one of #{UNITS.join(', ')}"
    end

    rows = user.workouts
      .where(performed_on: since..)
      .group(Arel.sql("date_trunc('#{unit}', performed_on)"))
      .order(Arel.sql("date_trunc('#{unit}', performed_on)"))
      .count

    rows.map { |period_start, days| { period_start: period_start.to_date, days: days } }
  end
end
