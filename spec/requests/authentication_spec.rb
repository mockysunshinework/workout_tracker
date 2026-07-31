require "rails_helper"

RSpec.describe "Authentication", type: :request do
  describe "Devise 標準画面の表示" do
    it "ログイン画面が表示される" do
      get new_user_session_path
      expect(response).to have_http_status(:ok)
    end

    it "会員登録画面が表示される" do
      get new_user_registration_path
      expect(response).to have_http_status(:ok)
    end

    it "会員登録画面に name 入力欄がある" do
      get new_user_registration_path
      expect(response.body).to include('name="user[name]"')
    end
  end

  describe "認証ガード" do
    it "未ログインで root にアクセスするとログイン画面へリダイレクトする" do
      get root_path
      expect(response).to redirect_to(new_user_session_path)
    end

    it "ログイン済みなら root が表示される" do
      sign_in create(:user)
      get root_path
      expect(response).to have_http_status(:ok)
    end
  end

  describe "会員登録" do
    it "有効な情報で登録するとユーザーが作成され root へ遷移する" do
      expect {
        post user_registration_path, params: {
          user: {
            name: "山田太郎",
            email: "new@example.com",
            password: "password123",
            password_confirmation: "password123"
          }
        }
      }.to change(User, :count).by(1)
      expect(response).to redirect_to(root_path)
    end
  end

  describe "ログイン・ログアウト" do
    let!(:user) { create(:user, email: "member@example.com", password: "password123") }

    it "正しい資格情報でログインすると root へ遷移する" do
      post user_session_path, params: { user: { email: "member@example.com", password: "password123" } }
      expect(response).to redirect_to(root_path)
    end

    it "ログアウトできる" do
      sign_in user
      delete destroy_user_session_path
      expect(response).to redirect_to(root_path)
    end
  end
end
