require "rails_helper"

# 5.5 バリデーションエラー等の日本語化（i18n）。
# 画面に出るメッセージ（flash / Devise）が日本語になることを request レベルで検証する。
RSpec.describe "Japanese messages", type: :request do
  let(:user) { create(:user) }

  describe "バリデーションエラー" do
    before { sign_in user }

    it "種目の重複追加エラーが日本語で表示される（属性名の翻訳含む）" do
      create(:exercise, user: user, name: "ベンチプレス")

      post exercises_path, params: { exercise: { name: "ベンチプレス" } }

      expect(flash[:alert]).to include("種目名")
      expect(flash[:alert]).to include("すでに存在します")
    end

    it "重量未入力（非自重種目）のエラーが日本語で表示される" do
      workout = create(:workout, user: user)
      barbell = create(:exercise, user: user, bodyweight: false)

      post workout_workout_sets_path(workout),
           params: { workout_set: { exercise_id: barbell.id, weight_kg: nil, reps: 10 } }

      expect(flash[:alert]).to include("重量")
      expect(flash[:alert]).to include("を入力してください")
    end

    it "使用中種目の削除エラーが日本語で表示される" do
      exercise = create(:exercise, user: user)
      create(:workout_set, workout: create(:workout, user: user), exercise: exercise)

      delete exercise_path(exercise)

      expect(flash[:alert]).to include("削除できません")
    end
  end

  describe "Devise メッセージ" do
    it "ログイン失敗のメッセージが日本語で表示される" do
      post user_session_path,
           params: { user: { email: user.email, password: "wrong-password" } }

      expect(flash[:alert]).to include("パスワード")
      expect(flash[:alert]).not_to include("Invalid")
    end
  end
end
