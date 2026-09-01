class LineWebhooksController < ApplicationController
  # LINE プラットフォームからの POST を受けるため、認証と CSRF 保護を本エンドポイントのみ除外する。
  # この 2 つの除外は CLAUDE.md セキュリティ方針で LINE Webhook にのみ許可されている（SPEC 4.2.4 / 8 章）。
  skip_before_action :authenticate_user!
  skip_forgery_protection

  def create
    signature = request.headers["X-Line-Signature"]
    return head :bad_request if signature.blank?

    events = LineBot.webhook_parser.parse(body: request.body.read, signature: signature)
    events.each do |event|
      # 登録済み（再送・並行受信）のイベントはブロックが実行されずスキップされる（SPEC 4.2.4）
      ProcessedLineEvent.record_once(event.webhook_event_id) do
        # 業務処理（記録保存・返信）は 8 章以降で実装する
      end
    end
    head :ok
  rescue Line::Bot::V2::WebhookParser::InvalidSignatureError
    head :bad_request
  end
end
