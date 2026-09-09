# LINE Messaging API クライアントの初期化と、同期処理内で許可された 2 つの呼び出し
# （SPEC 2.3 の例外: follow 時の Get profile と Reply）を一箇所にまとめる（7.3 / 8.9）。
# 資格情報は Rails credentials（7.2）。Webhook の署名検証・パースは webhook_parser（7.4）。
# メモ化はしない: いずれも生成が軽量で、テストでの資格情報差し替えを妨げないため（7.4）。
module LineBot
  # Webhook 同期処理の中で LINE を呼ぶため短くする（replyToken は受信後 1 分以内に使う: SPEC 10 章 #3）。
  # 決め値: 接続 3 秒・読み取り 5 秒
  HTTP_OPTIONS = { open_timeout: 3, read_timeout: 5 }.freeze

  module_function

  def client
    Line::Bot::V2::MessagingApi::ApiClient.new(channel_access_token: channel_access_token, http_options: HTTP_OPTIONS)
  end

  def webhook_parser
    Line::Bot::V2::WebhookParser.new(channel_secret: channel_secret)
  end

  def channel_secret
    Rails.application.credentials.dig(:line, :channel_secret)
  end

  def channel_access_token
    Rails.application.credentials.dig(:line, :channel_access_token)
  end

  # Get profile で表示名を取得する（SPEC 4.1.1）。取得できない場合（プロフィール未同意・ブロック中・
  # 通信障害）は nil を返し、呼び出し側がフォールバック名で登録を続行する。
  # SDK は 2xx 以外でも例外を投げず [body, status, headers] を返すため、status で判定する
  def fetch_display_name(line_user_id)
    profile, status, = client.get_profile_with_http_info(user_id: line_user_id)
    return profile.display_name.presence if status == 200

    Rails.logger.warn("LINE Get profile failed: status=#{status}")
    nil
  rescue StandardError => e
    Rails.logger.warn("LINE Get profile failed: #{e.class}")
    nil
  end

  # Reply API でテキスト 1 件を返信する（SPEC 2.3）。DB コミット後に呼ぶこと。
  # 失敗してもリトライ・ロールバックせずログに留め、false を返す（返信の成否を記録の保存に波及させない）
  def reply(reply_token, text)
    request = Line::Bot::V2::MessagingApi::ReplyMessageRequest.new(
      reply_token: reply_token,
      messages: [ Line::Bot::V2::MessagingApi::TextMessage.new(text: text) ]
    )
    _body, status, = client.reply_message_with_http_info(reply_message_request: request)
    return true if status == 200

    Rails.logger.warn("LINE Reply failed: status=#{status}")
    false
  rescue StandardError => e
    Rails.logger.warn("LINE Reply failed: #{e.class}")
    false
  end
end
