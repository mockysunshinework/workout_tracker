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
    when Line::Bot::V2::Webhook::PostbackEvent
      handle_postback(event)
    else
      # 未対応のイベントは冪等 ID だけ記録して受領する
      ProcessedLineEvent.record_once(event.webhook_event_id)
    end
  end

  # SPEC 4.2.1 message（テキスト）: コマンドならその応答（11 章）、記録フォーマットなら保存してエコーバック（9.4）、
  # 失敗や記録の形でないテキストは案内を返信（9.5）、未知の種目を含むなら全行を保留して候補を
  # Quick Reply で提示（10.5）。記録日は受信日（JST。Date.current はアプリのタイムゾーン = Tokyo）。
  # テキスト以外のメッセージは冪等 ID だけ記録して受領する
  def handle_message(event)
    # テキストメッセージでない場合には、このイベントは処理済みと記録して終了
    return ProcessedLineEvent.record_once(event.webhook_event_id) unless event.message.is_a?(Line::Bot::V2::Webhook::TextMessageContent)

    # follow を受信していない送信者も同じ find_or_create で作成して通常どおり処理する（SPEC 4.1.1 の自己修復）。
    # 表示名は取得しない（Get profile は follow 時だけ許可された外部呼び出し: SPEC 2.3）ので
    # フォールバック名になり、次回の LINE Login で更新される。record_once の外で行うのは、
    # 並行作成の unique 制約違反をトランザクション内で起こすと以降の SQL が失敗するため
    user = User.find_or_create_from_line!(line_user_id: event.source.user_id, display_name: nil)

    text = buttons = nil
    # このWebhookイベントをまだ処理していなければ、ブロックの中を実行する
    # 処理済みの場合はこのブロックは実行されない
    ProcessedLineEvent.record_once(event.webhook_event_id) do
      text, buttons = message_reply(user, event.message.text)
    end

    LineBot.reply(event.reply_token, text, buttons: buttons) if text
  end

  # テキスト → [返信文, Quick Reply のボタン]。コマンド（SPEC 4.2.1・11 章）を先に判定し、
  # 一致しなければ記録として処理する
  def message_reply(user, text)
    case LineCommand.match(text)
    when :help then [ LineMessages.help, [] ]
    else reply_for(RecordMessageHandler.call(user: user, text: text, performed_on: Date.current))
    end
  end

  # SPEC 4.2.1 postback（Quick Reply のボタン選択）: 保留中の入力の確定・新規登録・キャンセルと、
  # 別名確認の はい／いいえ（SPEC 4.3.1(3)(4)・10.6）。message と同じく record_once の中で処理し、コミット後に返信する
  def handle_postback(event)
    user = User.find_or_create_from_line!(line_user_id: event.source.user_id, display_name: nil)

    outcome = nil
    ProcessedLineEvent.record_once(event.webhook_event_id) do
      outcome = PostbackHandler.call(user: user, data: event.postback.data)
    end
    return unless outcome

    text, buttons = postback_reply_for(outcome)
    LineBot.reply(event.reply_token, text, buttons: buttons)
  end

  # PostbackHandler::Outcome → [返信文, Quick Reply のボタン]。候補選択で保存したときは、エコーバックの末尾に
  # 別名確認の 1 行と はい／いいえ を付ける（独立メッセージにしない: SPEC 4.3.1(4)）
  def postback_reply_for(outcome)
    case outcome.status
    when :saved then with_alias_question(LineMessages.recorded(outcome.saved), outcome.exercise_alias)
    when :unknown_exercises
      [ LineMessages.candidate_prompt(pending: outcome.pending, candidates: outcome.candidates),
        LineMessages.candidate_buttons(pending: outcome.pending, candidates: outcome.candidates) ]
    when :invalid then [ LineMessages.invalid(outcome.invalid_messages), [] ]
    when :cancelled then [ LineMessages.cancelled, [] ]
    when :stale_pending then [ LineMessages.stale_pending, [] ]
    when :alias_confirmed then with_alias_question(LineMessages.alias_confirmed(outcome.exercise_alias), outcome.next_alias)
    when :alias_declined then with_alias_question(LineMessages.alias_declined(outcome.exercise_alias), outcome.next_alias)
    when :stale_alias then [ LineMessages.stale_alias, [] ]
    end
  end

  # 返信文の末尾に別名確認の 1 行を添え、はい／いいえ のボタンを付ける。確認する別名が無ければ文だけを返す。
  # 別名確認は 1 件ずつ: 保存のエコーバックに 1 件目、はい／いいえ の返信に次の 1 件を乗せる（SPEC 4.3.1(4)）
  def with_alias_question(text, exercise_alias)
    return [ text, [] ] unless exercise_alias

    [ "#{text}\n#{LineMessages.alias_question(exercise_alias)}", LineMessages.alias_buttons(exercise_alias) ]
  end

  # Outcome → [返信文, Quick Reply のボタン]。未知の種目は候補提示（SPEC 4.3.1(2)。確定処理は postback）
  def reply_for(outcome)
    case outcome.status
    when :saved then [ LineMessages.recorded(outcome.saved), [] ]
    when :parse_failed then [ LineMessages.parse_failed(outcome.parse_result), [] ]
    when :unrecognized then [ LineMessages.unrecognized, [] ]
    when :invalid then [ LineMessages.invalid(outcome.invalid_messages), [] ]
    when :unknown_exercises
      [ LineMessages.candidate_prompt(pending: outcome.pending, candidates: outcome.candidates),
        LineMessages.candidate_buttons(pending: outcome.pending, candidates: outcome.candidates) ]
    end
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
