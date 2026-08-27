class HomeController < ApplicationController
  def index
    # 当週は月曜起点（TrainingFrequency の ISO 週と整合）
    week = Date.current.all_week
    @weekly_days = current_user.workouts.where(performed_on: week).count
    @weekly_sets = WorkoutSet.joins(:workout)
                             .where(workouts: { user_id: current_user.id, performed_on: week })
                             .count
    # グラフの種目セレクト（プリセット＋自分の種目）
    @exercises = Exercise.available_for(current_user).order(:id)
  end
end
