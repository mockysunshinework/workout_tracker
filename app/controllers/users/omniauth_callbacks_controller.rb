module Users
  # LINE Login のコールバック（SPEC 4.1.2）。state / nonce の照合と ID トークンの署名検証は
  # OmniAuth（omniauth_openid_connect）がここに来る前に済ませている。
  # 失敗時は Devise 既定の failure アクション（ログイン画面へ戻しエラー表示）に任せる。
  class OmniauthCallbacksController < Devise::OmniauthCallbacksController
    def line
      auth = request.env["omniauth.auth"]
      # SPEC 4.1.1: 初回は自動作成、以降は表示名を LINE の最新値に更新する
      user = User.find_or_create_from_line!(
        line_user_id: auth.uid,
        display_name: auth.info.name,
        update_name: true
      )

      set_flash_message(:notice, :success, kind: "LINE") if is_navigational_format?
      sign_in_and_redirect user, event: :authentication
    end

    protected

    # Devise 既定は new_session_path(scope) を呼ぶが、その URL ヘルパは database_authenticatable の
    # sessions ルートを devise_for が生成した場合にしか定義されない（本アプリは routes.rb で明示的に張っている）
    def after_omniauth_failure_path_for(_scope)
      new_user_session_path
    end
  end
end
