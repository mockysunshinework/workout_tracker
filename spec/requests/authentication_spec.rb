require "rails_helper"

# 8.7 Web ログインの LINE Login 化（SPEC 4.1.1 / 4.1.2）。
# LINE との往復は OmniAuth のテストモードで置き換える（rails_helper で test_mode を有効化）。
RSpec.describe "Authentication (LINE Login)", type: :request do
  let(:line_user_id) { "U1234567890abcdef1234567890abcdef" }

  def mock_line_login(uid: line_user_id, name: "もとなが")
    OmniAuth.config.mock_auth[:line] = OmniAuth::AuthHash.new(
      provider: "line",
      uid: uid,
      info: { name: name, image: "https://example.com/profile.jpg" },
      credentials: { token: "dummy-access-token", id_token: "dummy-id-token" }
    )
  end

  # テストモードでは POST /users/auth/line がコールバックへリダイレクトされる
  def login_via_line
    post user_line_omniauth_authorize_path
    follow_redirect!
  end

  describe "ログイン画面" do
    it "「LINE でログイン」ボタン（POST /users/auth/line）だけがあり、メール/パスワード欄は無い" do
      get new_user_session_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(user_line_omniauth_authorize_path)
      expect(response.body).not_to include('name="user[email]"')
      expect(response.body).not_to include('name="user[password]"')
    end

    it "ログイン済みで開くと root へリダイレクトする" do
      sign_in create(:user)

      get new_user_session_path

      expect(response).to redirect_to(root_path)
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

  describe "LINE Login コールバック（SPEC 4.1.1 自動作成）" do
    it "未登録の LINE ユーザーなら User を作成してログインし、root へ遷移する" do
      mock_line_login

      expect { login_via_line }.to change(User, :count).by(1)
      expect(response).to redirect_to(root_path)

      user = User.find_by!(line_user_id: line_user_id)
      expect(user.name).to eq "もとなが"

      follow_redirect!
      expect(response).to have_http_status(:ok) # ログイン状態で root が表示される
    end

    it "登録済みの LINE ユーザーなら既存 User でログインし、表示名を最新値に更新する" do
      existing = create(:user, line_user_id: line_user_id, name: "以前の名前")
      mock_line_login(name: "新しい名前")

      expect { login_via_line }.not_to change(User, :count)
      expect(response).to redirect_to(root_path)
      expect(existing.reload.name).to eq "新しい名前"
    end

    it "表示名が取得できなければフォールバック名で作成する" do
      mock_line_login(name: nil)

      login_via_line

      expect(User.find_by!(line_user_id: line_user_id).name).to eq User::FALLBACK_NAME
    end

    it "LINE 側で失敗するとログイン画面へ戻り、エラーを表示する" do
      OmniAuth.config.mock_auth[:line] = :invalid_credentials

      expect { login_via_line }.not_to change(User, :count)
      # OmniAuth の失敗 → Devise の failure アクション → ログイン画面
      follow_redirect! while response.redirect? && response.location != new_user_session_url
      expect(response).to redirect_to(new_user_session_path)
      expect(flash[:alert]).to be_present
    end
  end

  # omniauth_openid_connect は OmniAuth 標準の callback_url からは redirect_uri を組み立てず、
  # client_options.redirect_uri をそのまま使う。未指定だと LINE の認可 URL に redirect_uri が付かず
  # LINE 側が 400 を返す（8.7 のブラウザ確認で発覚）。setup フックで毎リクエスト与えていることを守る。
  # テストモードではリクエストフェーズが丸ごと置き換わるため、この example だけ実物の request_phase を通す
  describe "LINE への認可リクエスト（redirect_uri の付与）" do
    around do |example|
      OmniAuth.config.test_mode = false
      example.run
    ensure
      OmniAuth.config.test_mode = true
    end

    before do
      # discovery（外部 HTTP）と、credentials 由来の identifier（CI では nil）に依存しないよう、
      # エンドポイント設定済みのクライアントを直接与える
      allow_any_instance_of(OmniAuth::Strategies::OpenIDConnect).to receive(:discover!)
      allow_any_instance_of(OmniAuth::Strategies::OpenIDConnect).to receive(:client).and_return(
        OpenIDConnect::Client.new(
          identifier: "test-channel-id",
          secret: "test-channel-secret",
          authorization_endpoint: "https://access.line.me/oauth2/v2.1/authorize"
        )
      )
    end

    it "認可 URL の redirect_uri がリクエストのホスト＋コールバックパスになる" do
      post user_line_omniauth_authorize_path

      expect(response).to have_http_status(:found)
      location = URI.parse(response.location)
      expect(location.host).to eq "access.line.me"
      params = Rack::Utils.parse_query(location.query)
      expect(params["redirect_uri"]).to eq "http://www.example.com/users/auth/line/callback"
      expect(params["client_id"]).to eq "test-channel-id"
      expect(params["scope"]).to include("openid")
    end
  end

  describe "ログアウト" do
    it "ログアウトすると未ログインに戻り、root がログイン画面へリダイレクトする" do
      sign_in create(:user)

      delete destroy_user_session_path

      expect(response).to redirect_to(root_path)
      get root_path
      expect(response).to redirect_to(new_user_session_path)
    end
  end
end
