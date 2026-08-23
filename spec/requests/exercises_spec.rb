require "rails_helper"

# 5.4 種目管理画面（SPEC 4.4 画面 5）: 独自種目の追加・名称変更・削除、プリセット一覧表示
RSpec.describe "Exercises", type: :request do
  let(:user) { create(:user) }

  describe "認証ガード" do
    it "未ログインでアクセスするとログイン画面へリダイレクトする" do
      get exercises_path

      expect(response).to redirect_to(new_user_session_path)
    end
  end

  describe "一覧表示" do
    before { sign_in user }

    it "自分の独自種目とプリセットが表示される" do
      mine = create(:exercise, user: user, name: "マイ種目")
      preset = create(:exercise, :preset, name: "ベンチプレス")

      get exercises_path

      expect(response.parsed_body.css("#exercise_#{mine.id}")).to be_present
      expect(response.parsed_body.css("#exercise_#{preset.id}")).to be_present
    end

    it "削除ボタンに確認ダイアログ用の data-turbo-confirm が付与される" do
      mine = create(:exercise, user: user, name: "マイ種目")

      get exercises_path

      # 属性が「削除ボタンに」付いていることまで固定する（行内の別要素では通らない）
      buttons = response.parsed_body.css("#exercise_#{mine.id} button[data-turbo-confirm]")
      expect(buttons.map(&:text)).to eq [ "削除" ]
    end

    it "他ユーザーの独自種目は表示されない" do
      others = create(:exercise, name: "他人の種目")

      get exercises_path

      expect(response.parsed_body.css("#exercise_#{others.id}")).to be_empty
      expect(response.body).not_to include("他人の種目")
    end
  end

  describe "独自種目の追加" do
    before { sign_in user }

    it "種目を追加でき、一覧へ戻る" do
      expect {
        post exercises_path,
             params: { exercise: { name: "ダンベルフライ", category: "胸", bodyweight: false } }
      }.to change { user.exercises.count }.by(1)

      expect(response).to redirect_to(exercises_path)
      expect(user.exercises.last.name).to eq "ダンベルフライ"
    end

    it "正規化後に重複する名前はエラーになり追加されない（ベンチぷれす vs ベンチプレス）" do
      create(:exercise, user: user, name: "ベンチプレス")

      expect {
        post exercises_path, params: { exercise: { name: "ベンチぷれす" } }
      }.not_to change { user.exercises.count }

      expect(flash[:alert]).to be_present
    end
  end

  describe "名称変更" do
    before { sign_in user }

    it "自分の種目の名称を変更できる" do
      exercise = create(:exercise, user: user, name: "旧名称")

      patch exercise_path(exercise), params: { exercise: { name: "新名称" } }

      expect(response).to redirect_to(exercises_path)
      expect(exercise.reload.name).to eq "新名称"
    end

    it "プリセットは変更できず 404 になる" do
      preset = create(:exercise, :preset, name: "ベンチプレス")

      expect {
        patch exercise_path(preset), params: { exercise: { name: "改名" } }
      }.not_to change { preset.reload.name }

      expect(response).to have_http_status(:not_found)
    end

    it "他ユーザーの種目は変更できず 404 になる" do
      others = create(:exercise, name: "他人の種目")

      expect {
        patch exercise_path(others), params: { exercise: { name: "改名" } }
      }.not_to change { others.reload.name }

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "削除" do
    before { sign_in user }

    it "未使用の種目は削除できる" do
      exercise = create(:exercise, user: user)

      delete exercise_path(exercise)

      expect(response).to redirect_to(exercises_path)
      expect(Exercise.exists?(exercise.id)).to be false
    end

    it "使用中の記録がある種目は削除できず、エラーが通知される（SPEC 4.3 の削除制限）" do
      exercise = create(:exercise, user: user)
      create(:workout_set, workout: create(:workout, user: user), exercise: exercise)

      delete exercise_path(exercise)

      expect(Exercise.exists?(exercise.id)).to be true
      expect(flash[:alert]).to be_present
    end

    it "プリセットは削除できず 404 になる" do
      preset = create(:exercise, :preset, name: "ベンチプレス")

      delete exercise_path(preset)

      expect(response).to have_http_status(:not_found)
      expect(Exercise.exists?(preset.id)).to be true
    end

    it "他ユーザーの種目は削除できず 404 になる" do
      others = create(:exercise)

      delete exercise_path(others)

      expect(response).to have_http_status(:not_found)
      expect(Exercise.exists?(others.id)).to be true
    end
  end
end
