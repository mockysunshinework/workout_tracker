class WorkoutSetsController < ApplicationController
  before_action :set_workout

  def create
    # 種目は「プリセット＋自分の種目」に限定して引く。他ユーザーの種目 id は 404
    exercise = Exercise.available_for(current_user).find(params.expect(workout_set: [ :exercise_id ])[:exercise_id])
    set = @workout.append_set(exercise: exercise, **set_params.to_h.symbolize_keys)

    if set.persisted?
      redirect_to @workout, notice: "セットを追加しました"
    else
      redirect_to @workout, alert: set.errors.full_messages.join("、")
    end
  end

  def update
    set = @workout.workout_sets.find(params[:id])

    if set.update(set_params)
      redirect_to @workout, notice: "セットを更新しました"
    else
      redirect_to @workout, alert: set.errors.full_messages.join("、")
    end
  end

  def destroy
    set = @workout.workout_sets.find(params[:id])
    @workout.remove_set(set)

    redirect_to @workout, notice: "セットを削除しました"
  end

  private

  def set_workout
    @workout = current_user.workouts.find(params[:workout_id])
  end

  # set_number は採番・繰り上げがシステム管理のため受け付けない（SPEC 4.5）
  def set_params
    params.expect(workout_set: [ :weight_kg, :reps ])
  end
end
