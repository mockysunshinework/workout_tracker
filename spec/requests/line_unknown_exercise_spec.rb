require "rails_helper"

# 10.5 未知の種目を含む記録 → 全行を保留し、Quick Reply で候補を提示する（SPEC 4.3.1(2)(3)、ボタン構成は 10.2）。
# LINE API（Reply）は LineBot のクライアントを差し替えてモックする（8.9 / 9.4 と同じ方式）
RSpec.describe "LINE Webhook: 未知の種目と候補提示", type: :request do
  let(:channel_secret) { "test-channel-secret" }
  let(:line_user_id) { "U1234567890abcdef1234567890abcdef" }
  let(:client) { instance_double(Line::Bot::V2::MessagingApi::ApiClient) }
  let!(:user) { create(:user, line_user_id: line_user_id) }
  let!(:bench) { create(:exercise, :preset, name: "ベンチプレス") }
  let!(:incline) { create(:exercise, :preset, name: "インクラインベンチプレス") }

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

  def text_event(text, webhook_event_id: "01MESSAGE00000000000000003", is_redelivery: false)
    {
      type: "message", message: { type: "text", id: "468789577898262530", text: text, quoteToken: "q-token" },
      webhookEventId: webhook_event_id, deliveryContext: { isRedelivery: is_redelivery },
      timestamp: 1_789_000_000_000, source: { type: "user", userId: line_user_id },
      replyToken: "reply-token-1", mode: "active"
    }
  end

  # 最後に送ろうとした返信メッセージ（1 件目）
  def replied_message
    message = nil
    expect(client).to have_received(:reply_message_with_http_info).at_least(:once) do |reply_message_request:|
      message = reply_message_request.messages.first
    end
    message
  end

  it "未知の種目を含む記録は全行を保留し、何も保存せず、候補を Quick Reply で返信する" do
    expect { post_event(text_event("ベンチプレス60/5/3\nベンチ70/3")) }
      .to change(PendingWorkoutEntry, :count).by(1).and change(WorkoutSet, :count).by(0)

    expect(response).to have_http_status(:ok)
    pending = PendingWorkoutEntry.sole
    expect(pending.user).to eq user
    expect(pending.source_text).to eq "ベンチプレス60/5/3\nベンチ70/3"
    expect(pending.parsed_lines.map { |l| l["exercise_id"] }).to eq [ bench.id, nil ]

    message = replied_message
    expect(message.text).to eq "「ベンチ」に一致する種目がありません。どれを記録しますか？"
    actions = message.quick_reply.items.map(&:action)
    expect(actions.map(&:label)).to eq [ "ベンチプレス", "インクラインベンチプレス", "新規種目として登録", "キャンセル" ]
    expect(actions.map(&:data)).to eq [
      "action=choose&pending_id=#{pending.id}&exercise_id=#{bench.id}",
      "action=choose&pending_id=#{pending.id}&exercise_id=#{incline.id}",
      "action=create&pending_id=#{pending.id}",
      "action=cancel&pending_id=#{pending.id}"
    ]
  end

  it "候補がない種目は新規登録とキャンセルだけを提示する" do
    post_event(text_event("ランジ20/10"))

    message = replied_message
    expect(message.text).to eq "「ランジ」に一致する種目がありません。新規種目として登録しますか？"
    expect(message.quick_reply.items.map { |i| i.action.label }).to eq [ "新規種目として登録", "キャンセル" ]
  end

  it "保留中に別の記録メッセージが来たら既存の保留を破棄して新しい入力を優先する（後勝ち・id 再採番）" do
    post_event(text_event("ベンチ60/5", webhook_event_id: "01MESSAGE00000000000000003"))
    old = PendingWorkoutEntry.sole

    post_event(text_event("スクワ80/5", webhook_event_id: "01MESSAGE00000000000000004"))

    expect(PendingWorkoutEntry.where(user: user).count).to eq 1
    replaced = PendingWorkoutEntry.sole
    expect(replaced.id).not_to eq old.id
    expect(replaced.source_text).to eq "スクワ80/5"
    expect(replied_message.quick_reply.items.first.action.data).to include("pending_id=#{replaced.id}")
  end

  it "再送（同一 webhookEventId）では保留を作り直さず、再返信もしない" do
    post_event(text_event("ベンチ60/5"))
    pending = PendingWorkoutEntry.sole

    post_event(text_event("ベンチ60/5", is_redelivery: true))

    expect(PendingWorkoutEntry.sole.id).to eq pending.id
    expect(client).to have_received(:reply_message_with_http_info).once
  end

  describe "並行受信で保留の一意制約に違反した場合（SPEC 4.3.1(3): 一時的な障害として 500 → 再送）" do
    around do |example|
      original = Rails.application.env_config["action_dispatch.show_exceptions"]
      Rails.application.env_config["action_dispatch.show_exceptions"] = :all
      example.run
    ensure
      Rails.application.env_config["action_dispatch.show_exceptions"] = original
    end

    it "500 を返し、冪等 ID も登録されない（再送でやり直せる）" do
      allow(PendingWorkoutEntry).to receive(:replace_for!).and_raise(ActiveRecord::RecordNotUnique, "duplicate key value")

      post_event(text_event("ベンチ60/5"))

      expect(response).to have_http_status(:internal_server_error)
      expect(ProcessedLineEvent.count).to eq 0
      expect(client).not_to have_received(:reply_message_with_http_info)
    end
  end
end
