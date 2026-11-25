require "rails_helper"

# 11 章 コマンド（SPEC 4.2.1）: テキストがコマンドに一致したら、記録としては扱わずコマンドの応答を返信する。
# LINE API（Reply）は LineBot のクライアントを差し替えてモックする（8.9 / 9.4 と同じ方式）
RSpec.describe "LINE Webhook: コマンド", type: :request do
  let(:channel_secret) { "test-channel-secret" }
  let(:line_user_id) { "U1234567890abcdef1234567890abcdef" }
  let(:client) { instance_double(Line::Bot::V2::MessagingApi::ApiClient) }
  let!(:user) { create(:user, line_user_id: line_user_id) }

  before do
    allow(LineBot).to receive(:channel_secret).and_return(channel_secret)
    allow(LineBot).to receive(:client).and_return(client)
    allow(client).to receive(:reply_message_with_http_info).and_return([ nil, 200, {} ])
  end

  def post_event(event)
    content = { destination: "U0000", events: [ event ] }.to_json
    signature = Base64.strict_encode64(OpenSSL::HMAC.digest("SHA256", channel_secret, content))
    post webhooks_line_path, params: content,
         headers: { "CONTENT_TYPE" => "application/json", "X-Line-Signature" => signature }
  end

  def text_event(text, webhook_event_id: "01MESSAGE00000000000000003")
    {
      type: "message", message: { type: "text", id: "468789577898262530", text: text, quoteToken: "q-token" },
      webhookEventId: webhook_event_id, deliveryContext: { isRedelivery: false },
      timestamp: 1_789_000_000_000, source: { type: "user", userId: line_user_id },
      replyToken: "reply-token-1", mode: "active"
    }
  end

  def replied_text
    texts = []
    expect(client).to have_received(:reply_message_with_http_info).once do |reply_message_request:|
      expect(reply_message_request.reply_token).to eq "reply-token-1"
      texts.concat(reply_message_request.messages.map(&:text))
    end
    texts.join
  end

  # 11.1
  describe "ヘルプ" do
    it "記録フォーマットとコマンド一覧だけを返信する（読み取り失敗の前置きを付けない）" do
      post_event(text_event("ヘルプ"))

      expect(response).to have_http_status(:ok)
      expect(replied_text).to eq LineMessages.help
      expect(LineMessages.help).to include("ベンチプレス60/5/3").and include("「今日」").and include("「履歴」").and include("「ヘルプ」")
    end

    it "前後の空白（全角を含む）・改行と半角カナは無視して一致させる" do
      post_event(text_event(" ﾍﾙﾌﾟ　\n"))

      expect(replied_text).to eq LineMessages.help
    end

    it "コマンドを含むだけの文は一致させず、その他テキストとして扱う" do
      post_event(text_event("ヘルプお願いします"))

      expect(replied_text).to include("記録として読み取れませんでした。")
    end

    it "何も保存せず、保留中の入力も消さない" do
      pending_entry = create(:pending_workout_entry, user: user)

      post_event(text_event("ヘルプ"))

      expect(Workout.count).to eq 0
      expect(PendingWorkoutEntry.exists?(pending_entry.id)).to be true
    end

    it "同じイベントの再送には返信しない（冪等性・SPEC 4.2.4）" do
      2.times { post_event(text_event("ヘルプ")) }

      expect(client).to have_received(:reply_message_with_http_info).once
    end
  end
end
