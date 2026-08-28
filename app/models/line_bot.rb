# LINE Messaging API クライアントの初期化を一箇所にまとめる（7.3）。
# 資格情報は Rails credentials（7.2）。Reply API 呼び出し（9 章）と
# Webhook の署名検証・パース（7.4）で使う。
module LineBot
  module_function

  def client
    @client ||= Line::Bot::V2::MessagingApi::ApiClient.new(
      channel_access_token: Rails.application.credentials.dig(:line, :channel_access_token)
    )
  end

  def webhook_parser
    @webhook_parser ||= Line::Bot::V2::WebhookParser.new(
      channel_secret: Rails.application.credentials.dig(:line, :channel_secret)
    )
  end
end
