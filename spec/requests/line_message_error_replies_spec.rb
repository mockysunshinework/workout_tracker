require "rails_helper"

# 9.5 エラー応答（SPEC 4.2.1 / 4.2.3 / 4.1.1）: パース失敗・その他テキスト・User 未作成の自己修復・
# 保存時の検証エラー。いずれも DB には何も保存せず（自己修復の User 作成を除く）、案内を返信する。
# LINE API（Reply）は LineBot のクライアントを差し替えてモックする（8.9 / 9.4 と同じ方式）
RSpec.describe "LINE Webhook: エラー応答", type: :request do
  let(:channel_secret) { "test-channel-secret" }
  let(:line_user_id) { "U1234567890abcdef1234567890abcdef" }
  let(:client) { instance_double(Line::Bot::V2::MessagingApi::ApiClient) }
  let!(:bench) { create(:exercise, :preset, name: "ベンチプレス") }

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

  def text_event(text, webhook_event_id: "01MESSAGE00000000000000002")
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

  context "User が存在する送信者" do
    let!(:user) { create(:user, line_user_id: line_user_id) }

    it "パース失敗: 失敗した行と入力例を返信し、成功した行も含めて DB へ一切保存しない" do
      post_event(text_event("ベンチプレス60/5/3\nベンチプレス60/\nベンチプレス70/3"))

      expect(response).to have_http_status(:ok)
      expect(Workout.count).to eq 0
      expect(WorkoutSet.count).to eq 0
      expect(replied_text).to include("2行目「ベンチプレス60/」").and include("保存していません").and include(LineMessages.input_guide)
    end

    it "その他テキスト（記録の形でない）: 入力方法の案内を返信し、何も保存しない" do
      post_event(text_event("こんにちは"))

      expect(response).to have_http_status(:ok)
      expect(Workout.count).to eq 0
      expect(replied_text).to include(LineMessages.input_guide).and include("記録として読み取れませんでした。")
    end

    it "保存時の検証エラー（重量が必要な種目に自重）: 理由を返信し、何も保存しない" do
      post_event(text_event("ベンチプレス/10/3"))

      expect(response).to have_http_status(:ok)
      expect(Workout.count).to eq 0
      expect(replied_text).to include("ベンチプレス").and include("重量").and include("保存していません")
    end

    it "エラー返信が失敗（400）しても 200 を返す" do
      allow(client).to receive(:reply_message_with_http_info).and_return([ nil, 400, {} ])
      allow(Rails.logger).to receive(:warn)

      post_event(text_event("こんにちは"))

      expect(response).to have_http_status(:ok)
    end
  end

  context "User が未作成の送信者（follow を受信していない line_user_id・SPEC 4.1.1 自己修復）" do
    it "フォールバック名で User を作成してから通常どおり処理し、記録を保存してエコーバックする" do
      expect { post_event(text_event("ベンチプレス60/5/3")) }.to change(User, :count).by(1)

      user = User.find_by!(line_user_id: line_user_id)

      expect(user.name).to eq User::FALLBACK_NAME
      expect(user.workouts.size).to eq(1)
      expect(user.workouts.first.workout_sets.size).to eq(3)
      # expect(user.workouts.sole.workout_sets.count).to eq 3 <= 上２行を１行にまとめるとsoleメソッドを使う
      expect(replied_text).to include("ベンチプレス 60kg×5回×3セット")
      expect(replied_text).not_to include(LineMessages.input_guide)
    end

    it "記録の形でないテキストでも User を作成し、案内を返信する（Get profile は呼ばない）" do
      allow(client).to receive(:get_profile_with_http_info)

      expect { post_event(text_event("こんにちは")) }.to change(User, :count).by(1)

      expect(client).not_to have_received(:get_profile_with_http_info)
      expect(replied_text).to include(LineMessages.input_guide)
    end
  end
end
