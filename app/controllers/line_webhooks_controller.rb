class LineWebhooksController < ApplicationController
  # LINE プラットフォームからの POST を受けるため、認証と CSRF 保護を本エンドポイントのみ除外する。
  # この 2 つの除外は CLAUDE.md セキュリティ方針で LINE Webhook にのみ許可されている（SPEC 4.2.4 / 8 章）。
  skip_before_action :authenticate_user!
  skip_forgery_protection

  # 応答は SPEC 4.2.4 の 3 分類に従う:
  #   署名不正 = 400 / 業務エラー相当 = 200 / 一時的な障害 = 500（rescue せず LINE の再送で回復させる）
  def create
    signature = request.headers["X-Line-Signature"]
    return head :bad_request if signature.blank?

    begin
      events = LineBot.webhook_parser.parse(body: request.body.read, signature: signature)
    rescue Line::Bot::V2::WebhookParser::InvalidSignatureError
      return head :bad_request
    rescue StandardError => e
      # 正署名だが本文が Webhook として解釈できない（壊れた JSON / 形式違いの JSON 等）。
      # 再送でも回復せず返信先も持たないため、業務エラー相当として受領し記録のみ残す。
      # この rescue は parse 段階に限定する: 下のイベント処理まで覆うと業務処理の例外を
      # 200 で握りつぶし、500 → 再送のリカバリを壊すため
      Rails.logger.warn("Unparseable LINE webhook body: #{e.class}")
      return head :ok
    end

    events.each do |event|
      # 登録済み（再送・並行受信）のイベントはブロックが実行されずスキップされる（SPEC 4.2.4）
      # 冪等性（同じ Webhook が複数回来ても業務処理は 1 回だけ）を担保している
      ProcessedLineEvent.record_once(event.webhook_event_id) do
        # 業務処理（記録保存・返信）は 8 章以降で実装する
      end
    end
    head :ok
  end
end
