class WorkoutsController < ApplicationController
  def index
    workouts = current_user.workouts.with_set_stats.order(performed_on: :desc)
    if (month = parse_month(params[:month]))
      workouts = workouts.performed_in(month)
    end
    @workouts = workouts
    # 月フィルタの選択肢は記録が存在する月から作る
    @months = current_user.workouts.order(performed_on: :desc)
                          .pluck(:performed_on).map { |date| date.strftime("%Y-%m") }.uniq
  end

  def show
    # current_user 起点で取得する（CLAUDE.md セキュリティ方針）。
    # 他ユーザーの id は RecordNotFound → 404 になり、存在有無も区別させない。
    @workout = current_user.workouts.find(params[:id])
    # 表示順は種目（登録順）→ セット番号。仕様に記載がないため実装詳細として判断
    @workout_sets = @workout.workout_sets.includes(:exercise).order(:exercise_id, :set_number)
    # 追加フォームの種目選択肢（プリセット＋自分の種目）
    @exercises = Exercise.available_for(current_user).order(:id)
  end

  private

  # "YYYY-MM" 以外（未指定・不正値）は nil を返し、フィルタなしとして扱う
  def parse_month(value)
    Date.strptime(value.to_s, "%Y-%m")
  rescue ArgumentError
    nil
  end
end
