require "rails_helper"

# 8.2b LINE 連携設定画面（SPEC 4.4 画面 6）: 連携コード発行・連携状態表示・連携解除
RSpec.describe "Settings::Line", type: :request do
  let(:user) { create(:user) }

  describe "認証ガード" do
    it "未ログインはログイン画面へリダイレクトする" do
      get settings_line_path

      expect(response).to redirect_to(new_user_session_path)
    end
  end

  describe "GET /settings/line（状態表示）" do
    before { sign_in user }

    it "未連携なら「未連携」と発行ボタンを表示し、解除ボタンは表示しない" do
      get settings_line_path

      expect(response.body).to include("未連携")
      expect(response.body).to include("連携コードを発行")
      expect(response.body).not_to include("連携を解除")
    end

    it "連携済みなら「連携済み」と解除ボタンを表示する" do
      user.update_column(:line_user_id, "U1234567890abcdef1234567890abcdef")

      get settings_line_path

      expect(response.body).to include("連携済み")
      expect(response.body).to include("連携を解除")
    end

    it "有効期限内の連携コードを表示する" do
      code = user.issue_line_link_code!

      get settings_line_path

      expect(response.body).to include(code)
    end

    it "期限切れの連携コードは表示しない" do
      code = user.issue_line_link_code!
      user.update_column(:line_link_code_expires_at, 1.minute.ago)

      get settings_line_path

      expect(response.body).not_to include(code)
    end
  end

  describe "POST /settings/line/link_code（コード発行）" do
    before { sign_in user }

    it "コードを発行し、設定画面に表示される" do
      post link_code_settings_line_path

      expect(response).to redirect_to(settings_line_path)
      follow_redirect!
      expect(user.reload.line_link_code).to be_present
      expect(response.body).to include(user.line_link_code)
    end

    it "再発行するとコードが置き換わる" do
      first_code = user.issue_line_link_code!

      post link_code_settings_line_path

      expect(user.reload.line_link_code).not_to eq first_code
    end
  end

  describe "DELETE /settings/line（連携解除）" do
    before { sign_in user }

    it "line_user_id を NULL 化し、設定画面へ戻る" do
      user.update_column(:line_user_id, "U1234567890abcdef1234567890abcdef")

      delete settings_line_path

      expect(response).to redirect_to(settings_line_path)
      expect(user.reload.line_user_id).to be_nil
    end

    it "解除ボタンには確認ダイアログ用の data-turbo-confirm が付与される" do
      user.update_column(:line_user_id, "U1234567890abcdef1234567890abcdef")

      get settings_line_path

      buttons = response.parsed_body.css("button[data-turbo-confirm]")
      expect(buttons.map(&:text)).to include("連携を解除")
    end
  end
end
