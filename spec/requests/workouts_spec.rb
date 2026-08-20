require "rails_helper"

# 5.1 認証必須とユーザー分離の共通基盤（SPEC 2.3 / 8 章）。
# 画面の作り込みは 5.2 / 5.3 で行い、ここでは共通基盤の振る舞いのみを検証する。
RSpec.describe "Workouts", type: :request do
  describe "認証ガード" do
    it "未ログインで記録詳細にアクセスするとログイン画面へリダイレクトする" do
      workout = create(:workout)

      get workout_path(workout)

      expect(response).to redirect_to(new_user_session_path)
    end
  end

  describe "ユーザー分離（current_user 起点の取得）" do
    it "自分の workout は参照できる" do
      user = create(:user)
      workout = create(:workout, user: user)
      sign_in user

      get workout_path(workout)

      expect(response).to have_http_status(:ok)
    end

    it "他ユーザーの workout は 404 になる" do
      other_workout = create(:workout)
      sign_in create(:user)

      get workout_path(other_workout)

      expect(response).to have_http_status(:not_found)
    end

    it "存在しない id も 404 になる（存在有無を区別させない）" do
      sign_in create(:user)

      get workout_path(id: -1)

      expect(response).to have_http_status(:not_found)
    end
  end
end
