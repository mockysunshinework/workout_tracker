require "rails_helper"

# 9.4 記録メッセージ → 保存 → エコーバック（SPEC 4.2.2 / 4.2.3 / 4.2.4）。
# LINE API（Reply）は LineBot のクライアントを差し替えてモックする（8.9 と同じ方式）
RSpec.describe "LINE Webhook: 記録メッセージ", type: :request do
  let(:channel_secret) { "test-channel-secret" }
  let(:line_user_id) { "U1234567890abcdef1234567890abcdef" }
  let(:client) { instance_double(Line::Bot::V2::MessagingApi::ApiClient) }
  let!(:user) { create(:user, line_user_id: line_user_id) }
  let!(:bench) { create(:exercise, :preset, name: "ベンチプレス") }
  let!(:chinup) { create(:exercise, :preset, name: "懸垂", bodyweight: true) }
  # 受信日時は JST 2026-09-18 08:30（UTC では前日 23:30）。記録日は受信日（JST）
  let(:received_at) { Time.utc(2026, 9, 17, 23, 30) }
  let(:today) { Date.new(2026, 9, 18) }

  before do
    allow(LineBot).to receive(:channel_secret).and_return(channel_secret)
    allow(LineBot).to receive(:client).and_return(client)
    allow(client).to receive(:reply_message_with_http_info).and_return([ nil, 200, {} ])
    travel_to received_at
  end

  def post_event(event)
    content = { destination: "U0000", events: [ event ] }.to_json
    signature = Base64.strict_encode64(OpenSSL::HMAC.digest("SHA256", channel_secret, content))
    post webhooks_line_path, params: content,
         headers: { "CONTENT_TYPE" => "application/json", "X-Line-Signature" => signature }
  end

  def text_event(text, webhook_event_id: "01MESSAGE00000000000000001", is_redelivery: false)
    {
      type: "message", message: { type: "text", id: "468789577898262530", text: text, quoteToken: "q-token" },
      webhookEventId: webhook_event_id, deliveryContext: { isRedelivery: is_redelivery },
      timestamp: 1_789_000_000_000, source: { type: "user", userId: line_user_id },
      replyToken: "reply-token-1", mode: "active"
    }
  end

  def sticker_event
    {
      type: "message", message: { type: "sticker", id: "468789577898262531", packageId: "446", stickerId: "1988",
                                  stickerResourceType: "STATIC", quoteToken: "q-token" },
      webhookEventId: "01STICKER0000000000000001", deliveryContext: { isRedelivery: false },
      timestamp: 1_789_000_000_000, source: { type: "user", userId: line_user_id },
      replyToken: "reply-token-2", mode: "active"
    }
  end

  def replied_texts
    texts = []
    expect(client).to have_received(:reply_message_with_http_info).at_least(:once) do |reply_message_request:|
      texts.concat(reply_message_request.messages.map(&:text))
    end
    texts
  end

  def sets_of(exercise)
    user.workouts.find_by!(performed_on: today).workout_sets.where(exercise: exercise).order(:set_number)
        .map { |s| [ s.set_number, s.weight_kg, s.reps ] }
  end

  it "1 行の記録を受信日（JST）の workout に保存し、保存内容をエコーバックする" do
    expect { post_event(text_event("ベンチプレス60/5/3")) }.to change(Workout, :count).by(1)

    expect(response).to have_http_status(:ok)
    expect(user.workouts.sole.performed_on).to eq today
    expect(sets_of(bench)).to eq [ [ 1, 60, 5 ], [ 2, 60, 5 ], [ 3, 60, 5 ] ]

    expect(client).to have_received(:reply_message_with_http_info) do |reply_message_request:|
      expect(reply_message_request.reply_token).to eq "reply-token-1"
    end
    expect(replied_texts.join).to include("9/18").and include("ベンチプレス 60kg×5回×3セット（本日 計3セット）").and include("本日合計 3セット")
  end

  it "複数行（複数グループ・自重）を一括保存し、種目ごとにエコーバックする" do
    post_event(text_event("ベンチプレス60/5/2 65/5\n懸垂/10/3"))

    expect(sets_of(bench)).to eq [ [ 1, 60, 5 ], [ 2, 60, 5 ], [ 3, 65, 5 ] ]
    expect(sets_of(chinup)).to eq [ [ 1, nil, 10 ], [ 2, nil, 10 ], [ 3, nil, 10 ] ]
    text = replied_texts.join
    expect(text).to include("ベンチプレス 60kg×5回×2セット / 65kg×5回×1セット（本日 計3セット）")
    expect(text).to include("懸垂 自重×10回×3セット（本日 計3セット）")
    expect(text).to include("本日合計 6セット")
  end

  it "同じ種目を複数行に分けて送っても、1 行に並べた場合と同じエコーバックになる" do
    post_event(text_event("ベンチプレス60/5\n懸垂/10/2\nベンチプレス70/3"))

    expect(sets_of(bench)).to eq [ [ 1, 60, 5 ], [ 2, 70, 3 ] ]
    text = replied_texts.join
    expect(text).to include("ベンチプレス 60kg×5回×1セット / 70kg×3回×1セット（本日 計2セット）")
    expect(text.scan("ベンチプレス").size).to eq 1
    expect(text).to include("本日合計 4セット")
  end

  it "同日の追記は既存 workout にセット番号を続けて保存する（都度送信）" do
    workout = create(:workout, user: user, performed_on: today)
    (1..3).each { |n| create(:workout_set, workout: workout, exercise: bench, set_number: n, weight_kg: 60, reps: 5) }

    expect { post_event(text_event("ベンチプレス70/3")) }.not_to change(Workout, :count)

    expect(sets_of(bench).last).to eq [ 4, 70, 3 ]
    expect(replied_texts.join).to include("ベンチプレス 70kg×3回×1セット（本日 計4セット）")
  end

  it "返信は DB コミット後に行う（SPEC 2.3）" do
    persisted_at_reply = nil
    allow(client).to receive(:reply_message_with_http_info) do
      persisted_at_reply = WorkoutSet.count
      [ nil, 200, {} ]
    end

    post_event(text_event("ベンチプレス60/5/3"))

    expect(persisted_at_reply).to eq 3
  end

  # 9.6 Reply API の呼び出し条件（SPEC 2.3 / 4.2.4）: 返信の失敗は記録の保存に波及させず、リトライもせず、
  # ログに残すだけ。保存はコミット済みなので Webhook は 200 を返す（再送させない）
  it "Reply が 200 以外（期限切れ token の 400 等）でも記録は保存されたまま 200 を返し、警告ログを残す（リトライしない）" do
    allow(client).to receive(:reply_message_with_http_info).and_return([ nil, 400, {} ])
    allow(Rails.logger).to receive(:warn)

    post_event(text_event("ベンチプレス60/5/3"))

    expect(response).to have_http_status(:ok)
    expect(sets_of(bench).size).to eq 3
    expect(client).to have_received(:reply_message_with_http_info).once
    expect(Rails.logger).to have_received(:warn).with(/Reply failed.*400/i)
  end

  it "Reply が通信例外（タイムアウト等）でも記録は保存されたまま 200 を返し、例外クラスをログに残す" do
    allow(client).to receive(:reply_message_with_http_info).and_raise(Net::ReadTimeout)
    allow(Rails.logger).to receive(:warn)

    post_event(text_event("ベンチプレス60/5/3"))

    expect(response).to have_http_status(:ok)
    expect(sets_of(bench).size).to eq 3
    expect(Rails.logger).to have_received(:warn).with(/Reply failed.*Net::ReadTimeout/)
  end

  it "再送（同一 webhookEventId）では二重保存も再返信もしない" do
    post_event(text_event("ベンチプレス60/5/3"))

    expect { post_event(text_event("ベンチプレス60/5/3", is_redelivery: true)) }.not_to change(WorkoutSet, :count)
    expect(client).to have_received(:reply_message_with_http_info).once
  end

  it "未知の種目を含む場合は何も保存しない（候補提案の返信は 10 章）" do
    expect { post_event(text_event("ベンチプレス60/5\nベンチ60/5")) }.not_to change(WorkoutSet, :count)

    expect(response).to have_http_status(:ok)
    expect(Workout.count).to eq 0
  end

  it "テキスト以外のメッセージ（スタンプ等）は何も保存せず返信もしない" do
    post_event(sticker_event)

    expect(response).to have_http_status(:ok)
    expect(Workout.count).to eq 0
    expect(client).not_to have_received(:reply_message_with_http_info)
  end
end
