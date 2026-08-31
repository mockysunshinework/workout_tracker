class LineWebhooksController < ApplicationController
  # LINE プラットフォームからの POST を受けるため、認証と CSRF 保護を本エンドポイントのみ除外する。
  # この 2 つの除外は CLAUDE.md セキュリティ方針で LINE Webhook にのみ許可されている（SPEC 4.2.4 / 8 章）。
  skip_before_action :authenticate_user!
  skip_forgery_protection

  def create
    signature = request.headers["X-Line-Signature"]
    return head :bad_request if signature.blank?

    LineBot.webhook_parser.parse(body: request.body.read, signature: signature)
    # イベントの業務処理（冪等性・返信）は 7.5b 以降で実装する。7.4 は受信と署名検証まで
    head :ok
  rescue Line::Bot::V2::WebhookParser::InvalidSignatureError
    head :bad_request
  end
end
