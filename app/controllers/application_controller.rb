class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  # 全画面で認証を必須にする（SPEC 2.3 / 8 章）。Devise の画面（ログイン・登録等）は
  # 認証前に使うため除外する。LINE Webhook の除外は 8 章のエンドポイント実装時に行う。
  before_action :authenticate_user!, unless: :devise_controller?

  before_action :configure_permitted_parameters, if: :devise_controller?

  protected

  # Allow the additional `name` attribute on Devise sign up
  def configure_permitted_parameters
    devise_parameter_sanitizer.permit(:sign_up, keys: [ :name ])
  end
end
