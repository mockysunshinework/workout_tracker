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

    events.each { |event| handle(event) }
    head :ok
  end

  private

  # イベント種別ごとの業務処理。ドメイン層には SDK の型を渡さず、識別子・本文・返信先の素の値だけを渡す
  # （SPEC 2.3 多チャネル展開の境界）。返信は record_once（DB トランザクション）の外＝コミット後に行う
  def handle(event)
    case event
    when Line::Bot::V2::Webhook::FollowEvent
      handle_follow(event)
    when Line::Bot::V2::Webhook::UnfollowEvent
      handle_unfollow(event)
    when Line::Bot::V2::Webhook::MessageEvent
      handle_message(event)
    else
      # postback は 10 章で実装する。未対応のイベントは冪等 ID だけ記録して受領する
      ProcessedLineEvent.record_once(event.webhook_event_id)
    end
  end

  # SPEC 4.2.1 message（テキスト）: 記録フォーマットなら保存してエコーバック（9.4）。
  # 記録日は受信日（JST。Date.current はアプリのタイムゾーン = Tokyo）。
  # 未実装の分岐は冪等 ID だけ記録して受領する: テキスト以外のメッセージ / User 未作成の送信者（9.5 の
  # 自己修復）/ パース失敗・その他テキスト（9.5 の案内返信）/ 未知の種目（10 章の候補提案）
  def handle_message(event)
    # テキストメッセージでない場合には、このイベントは処理済みと記録して終了
    return ProcessedLineEvent.record_once(event.webhook_event_id) unless event.message.is_a?(Line::Bot::V2::Webhook::TextMessageContent)

    user = User.find_by(line_user_id: event.source.user_id)
    # アプリ側にUserが存在しないLINEユーザーなら筋トレ記録処理はせずにイベントを処理済とする
    return ProcessedLineEvent.record_once(event.webhook_event_id) unless user

    outcome = nil
    # このWebhookイベントをまだ処理していなければ、ブロックの中を実行する
    # 処理済みの場合はこのブロックは実行されない
    ProcessedLineEvent.record_once(event.webhook_event_id) do
      outcome = RecordMessageHandler.call(user: user, text: event.message.text, performed_on: Date.current)
    end
    # outcome が存在して、なおかつ保存成功なら先へ進む
    return unless outcome&.status == :saved

    LineBot.reply(event.reply_token, LineMessages.recorded(outcome.saved))
  end

  # SPEC 4.2.1 follow。表示名の取得（外部 API・SPEC 2.3 の例外）は新規ユーザーのときだけ行う
  # （既存ユーザーの表示名は follow で再取得しない: SPEC 4.1.1）
  def handle_follow(event)
    line_user_id = event.source.user_id
    display_name = User.exists?(line_user_id: line_user_id) ? nil : LineBot.fetch_display_name(line_user_id)

    greeting = nil
    # 登録済み（再送・並行受信）のイベントはブロックが実行されずスキップされる（SPEC 4.2.4）
    ProcessedLineEvent.record_once(event.webhook_event_id) do
      _user, greeting = User.follow_from_line!(line_user_id: line_user_id, display_name: display_name)
    end
    return unless greeting

    text = greeting == :welcome_back ? LineMessages.welcome_back : LineMessages.welcome
    LineBot.reply(event.reply_token, text)
  end

  # SPEC 4.2.1 unfollow。フラグのみ。返信先（replyToken）は無い
  def handle_unfollow(event)
    ProcessedLineEvent.record_once(event.webhook_event_id) do
      User.unfollow_from_line!(line_user_id: event.source.user_id)
    end
  end
end
