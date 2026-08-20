class WorkoutsController < ApplicationController
  def show
    # current_user 起点で取得する（CLAUDE.md セキュリティ方針）。
    # 他ユーザーの id は RecordNotFound → 404 になり、存在有無も区別させない。
    @workout = current_user.workouts.find(params[:id])
  end
end
