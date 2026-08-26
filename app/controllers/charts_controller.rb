class ChartsController < ApplicationController
  # 期間セレクトの選択肢（SPEC 4.4: 1/3/6 ヶ月、既定は 3）。許可外の値は既定に倒す
  ALLOWED_MONTHS = [ 1, 3, 6 ].freeze
  DEFAULT_MONTHS = 3

  def exercise_progress
    exercise = Exercise.available_for(current_user).find(params[:exercise_id])
    series = ExerciseProgress.series(user: current_user, exercise: exercise, since: since_date)

    render json: { exercise_id: exercise.id, months: period_months, series: series }
  end

  def training_frequency
    unit = TrainingFrequency::PERIOD_EXPRESSIONS.key?(params[:unit].to_s.to_sym) ? params[:unit].to_s : "month"
    counts = TrainingFrequency.counts(user: current_user, unit: unit, since: since_date)

    render json: { unit: unit, months: period_months, counts: counts }
  end

  private

  # 期間の月数（検証済みの params[:months]）。ActiveSupport の Integer#months と
  # 紛れないよう period_months と命名している
  def period_months
    requested = params[:months].to_i
    ALLOWED_MONTHS.include?(requested) ? requested : DEFAULT_MONTHS
  end

  def since_date
    period_months.months.ago.to_date
  end
end
