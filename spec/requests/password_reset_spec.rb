require "rails_helper"

RSpec.describe "PasswordReset", type: :request do
  # Devise の設定漏れを検出するため、実際に送られたメールを見る
  DEVISE_PLACEHOLDER_SENDER = "please-change-me-at-config-initializers-devise@example.com".freeze

  before { ActionMailer::Base.deliveries.clear }

  describe "リセットメールの送信" do
    let!(:user) { create(:user) }

    it "登録済みメールアドレスに対してメールを1通送信する" do
      post user_password_path, params: { user: { email: user.email } }

      expect(ActionMailer::Base.deliveries.size).to eq(1)
      expect(ActionMailer::Base.deliveries.last.to).to eq([ user.email ])
    end

    it "差出人が Devise の初期プレースホルダのままでない" do
      post user_password_path, params: { user: { email: user.email } }

      expect(ActionMailer::Base.deliveries.last.from).not_to include(DEVISE_PLACEHOLDER_SENDER)
    end

    it "本文にパスワード再設定用のリンクを含む" do
      post user_password_path, params: { user: { email: user.email } }

      expect(ActionMailer::Base.deliveries.last.body.encoded).to include("/users/password/edit?reset_password_token=")
    end

    it "未登録のメールアドレスにはメールを送信しない" do
      post user_password_path, params: { user: { email: "unknown@example.com" } }

      expect(ActionMailer::Base.deliveries).to be_empty
    end
  end
end
