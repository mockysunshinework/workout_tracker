class ExercisesController < ApplicationController
  def index
    @my_exercises = current_user.exercises.order(:id)
    @presets = Exercise.preset.order(:id)
  end

  def create
    exercise = current_user.exercises.new(exercise_params)

    if exercise.save
      redirect_to exercises_path, notice: "種目を追加しました"
    else
      redirect_to exercises_path, alert: exercise.errors.full_messages.join("、")
    end
  end

  def update
    # 変更・削除の対象は自分の独自種目のみ。プリセット（user_id NULL）と他ユーザーの種目は 404
    exercise = current_user.exercises.find(params[:id])

    if exercise.update(params.expect(exercise: [ :name ]))
      redirect_to exercises_path, notice: "種目名を変更しました"
    else
      redirect_to exercises_path, alert: exercise.errors.full_messages.join("、")
    end
  end

  def destroy
    exercise = current_user.exercises.find(params[:id])

    if exercise.destroy
      redirect_to exercises_path, notice: "種目を削除しました"
    else
      # 使用中の記録がある種目は削除不可（SPEC 4.3。restrict_with_error が :base に付ける）
      redirect_to exercises_path, alert: exercise.errors.full_messages.join("、")
    end
  end

  private

  def exercise_params
    params.expect(exercise: [ :name, :category, :bodyweight ])
  end
end
