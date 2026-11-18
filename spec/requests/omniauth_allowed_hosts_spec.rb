require "rails_helper"

# 8.10 LINE Login のコールバック URL に使うホストの検証（CVE-2026-63183 / GHSA-m27g-v28p-f9fx）。
# redirect_uri はリクエストのホストから組み立てている（config/initializers/devise.rb の setup フック）。
# Host / X-Forwarded-Host は偽装できるため、許可したホスト以外ではログインの開始もコールバックも受け付けない。
# omniauth 2.2.0 の検証は OmniAuth.config.allowed_hosts を設定したときだけ働く（未設定なら警告のみ）。
# 検証はテストモードでは通らない経路（request_call / callback_call）にあるので、ここではテストモードを切る
RSpec.describe "LINE Login: コールバック URL のホスト検証", type: :request do
  describe "許可していないホストからのリクエスト" do
    around do |example|
      OmniAuth.config.test_mode = false
      example.run
    ensure
      OmniAuth.config.test_mode = true
    end

    before do
      # discovery（外部 HTTP）と credentials 由来の identifier（CI では nil）に依存しないようにする
      # （authentication_spec の redirect_uri の example と同じ方式）
      allow_any_instance_of(OmniAuth::Strategies::OpenIDConnect).to receive(:discover!)
      allow_any_instance_of(OmniAuth::Strategies::OpenIDConnect).to receive(:client).and_return(
        OpenIDConnect::Client.new(
          identifier: "test-channel-id",
          secret: "test-channel-secret",
          authorization_endpoint: "https://access.line.me/oauth2/v2.1/authorize"
        )
      )
    end

    it "ログインの開始を拒否し、LINE へは送らずログイン画面へ戻す" do
      host! "evil.example"

      post user_line_omniauth_authorize_path

      expect(request.env["omniauth.error.type"]).to eq :invalid_host
      expect(response.location.to_s).not_to include("access.line.me")
      expect(response).to redirect_to(new_user_session_path)
      expect(flash[:alert]).to be_present
    end

    it "X-Forwarded-Host で偽装した場合も拒否する" do
      post user_line_omniauth_authorize_path, headers: { "X-Forwarded-Host" => "evil.example" }

      expect(request.env["omniauth.error.type"]).to eq :invalid_host
      expect(response.location.to_s).not_to include("access.line.me")
    end

    it "コールバックを拒否し、ユーザーの作成もログインもしない" do
      host! "evil.example"

      expect { get user_line_omniauth_callback_path, params: { code: "dummy-code", state: "dummy-state" } }
        .not_to change(User, :count)

      expect(request.env["omniauth.error.type"]).to eq :invalid_host
      expect(response).to redirect_to(new_user_session_path)

      get root_path
      expect(response).to redirect_to(new_user_session_path) # ログインしていない
    end

    it "許可したホストからのログイン開始は従来どおり LINE の認可 URL へ送る" do
      host! "localhost"

      post user_line_omniauth_authorize_path

      expect(response).to have_http_status(:found)
      expect(response.location).to start_with("https://access.line.me/oauth2/v2.1/authorize")
      expect(Rack::Utils.parse_query(URI.parse(response.location).query)["redirect_uri"])
        .to eq "http://localhost/users/auth/line/callback"
    end
  end

  # 許可するホストは環境変数 APP_ALLOWED_HOSTS（カンマ区切り）で渡す。本番のホスト名が未確定でも
  # コードを変えずに設定でき、ngrok 等のトンネルのホストも同じ方法で足せる。
  # initializer を環境と ENV を差し替えて読み直し、設定される値を確かめる
  describe "許可するホストの設定（config/initializers/omniauth.rb）" do
    let(:initializer) { Rails.root.join("config/initializers/omniauth.rb") }

    # 読み直した設定を、この spec の後に test 環境の値へ戻す（RSpec のスタブは after より前に解除されない
    # ため、スタブを明示的に外してから読み直す）
    after do
      RSpec::Mocks.space.reset_all
      load initializer
    end

    def load_with(env:, allowed_hosts: nil)
      allow(Rails).to receive(:env).and_return(ActiveSupport::EnvironmentInquirer.new(env))
      stub_const("ENV", ENV.to_h.merge("APP_ALLOWED_HOSTS" => allowed_hosts).compact)
      load initializer
      OmniAuth.config.allowed_hosts
    end

    it "production では APP_ALLOWED_HOSTS のホストだけを許可する（空白と空要素は取り除く）" do
      expect(load_with(env: "production", allowed_hosts: "app.example.jp, tunnel.example.net ,"))
        .to eq [ "app.example.jp", "tunnel.example.net" ]
    end

    it "production で APP_ALLOWED_HOSTS が未設定なら、どのホストも許可しない（nil ＝ 検証なし、にはしない）" do
      expect(load_with(env: "production")).to eq []
    end

    it "development では localhost と 127.0.0.1 を既定で許可し、APP_ALLOWED_HOSTS のホストを追加する" do
      expect(load_with(env: "development")).to eq [ "localhost", "127.0.0.1" ]
      expect(load_with(env: "development", allowed_hosts: "abc.ngrok-free.app"))
        .to eq [ "abc.ngrok-free.app", "localhost", "127.0.0.1" ]
    end

    it "test では request spec の既定ホスト（www.example.com）も許可する" do
      expect(load_with(env: "test")).to eq [ "localhost", "127.0.0.1", "www.example.com" ]
    end
  end
end
