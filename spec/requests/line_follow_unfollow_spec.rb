require "rails_helper"

# 8.9 follow / unfollow イベント処理（SPEC 4.1.1 / 4.2.1）。
# LINE API（Get profile / Reply）は LineBot のクライアントを差し替えてモックする（SPEC 9 章）。
RSpec.describe "LINE Webhook: follow / unfollow", type: :request do
  let(:channel_secret) { "test-channel-secret" }
  let(:line_user_id) { "U1234567890abcdef1234567890abcdef" }
  let(:client) { instance_double(Line::Bot::V2::MessagingApi::ApiClient) }

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

  def follow_event(webhook_event_id: "01FOLLOW000000000000000001", is_redelivery: false)
    {
      type: "follow", follow: { isUnblocked: false }, webhookEventId: webhook_event_id,
      deliveryContext: { isRedelivery: is_redelivery }, timestamp: 1_756_600_000_000,
      source: { type: "user", userId: line_user_id }, replyToken: "reply-token-1", mode: "active"
    }
  end

  def unfollow_event(webhook_event_id: "01UNFOLLOW00000000000000001")
    {
      type: "unfollow", webhookEventId: webhook_event_id,
      deliveryContext: { isRedelivery: false }, timestamp: 1_756_600_000_000,
      source: { type: "user", userId: line_user_id }, mode: "active"
    }
  end

  def stub_profile(display_name)
    profile = Line::Bot::V2::MessagingApi::UserProfileResponse.new(display_name: display_name, user_id: line_user_id)
    allow(client).to receive(:get_profile_with_http_info).with(user_id: line_user_id).and_return([ profile, 200, {} ])
  end

  def replied_texts
    texts = []
    expect(client).to have_received(:reply_message_with_http_info).at_least(:once) do |reply_message_request:|
      texts.concat(reply_message_request.messages.map(&:text))
    end
    texts
  end

  describe "follow（友だち追加）" do
    it "未登録なら Get profile の表示名で User を作成し、挨拶＋入力方法の案内を返信する" do
      stub_profile("もとなが")

      expect { post_event(follow_event) }.to change(User, :count).by(1)

      expect(response).to have_http_status(:ok)
      user = User.find_by!(line_user_id: line_user_id)
      expect(user.name).to eq "もとなが"
      expect(user.line_blocked).to be false

      expect(client).to have_received(:reply_message_with_http_info) do |reply_message_request:|
        expect(reply_message_request.reply_token).to eq "reply-token-1"
      end
      expect(replied_texts.join).to include("友だち追加").and include("kg")
    end

    it "ブロック中の既存ユーザーの再追加なら line_blocked を false に戻し、復帰の挨拶を返信する（Get profile は呼ばない）" do
      existing = create(:user, line_user_id: line_user_id, name: "以前の名前", line_blocked: true)
      allow(client).to receive(:get_profile_with_http_info)

      expect { post_event(follow_event) }.not_to change(User, :count)

      expect(existing.reload.line_blocked).to be false
      expect(existing.name).to eq "以前の名前"
      expect(client).not_to have_received(:get_profile_with_http_info)
      expect(replied_texts.join).to include("おかえり").and include("kg")
    end

    it "プロフィール取得に失敗（未同意等の 200 以外）してもフォールバック名で User を作成し、返信する" do
      allow(client).to receive(:get_profile_with_http_info).and_return([ '{"message":"Not found"}', 404, {} ])

      expect { post_event(follow_event) }.to change(User, :count).by(1)

      expect(User.find_by!(line_user_id: line_user_id).name).to eq User::FALLBACK_NAME
      expect(response).to have_http_status(:ok)
      expect(replied_texts).not_to be_empty
    end

    it "返信は DB コミット後に行う（SPEC 2.3: 返信の成否が記録の保存に影響しない）" do
      stub_profile("もとなが")
      persisted_at_reply = nil
      allow(client).to receive(:reply_message_with_http_info) do
        persisted_at_reply = User.exists?(line_user_id: line_user_id)
        [ nil, 200, {} ]
      end

      post_event(follow_event)

      expect(persisted_at_reply).to be true
    end

    it "返信が失敗（400）しても User は作成され、200 を返す" do
      stub_profile("もとなが")
      allow(client).to receive(:reply_message_with_http_info).and_return([ nil, 400, {} ])
      allow(Rails.logger).to receive(:warn)

      expect { post_event(follow_event) }.to change(User, :count).by(1)
      expect(response).to have_http_status(:ok)
    end

    it "再送（同一 webhookEventId）では作成も返信もしない" do
      stub_profile("もとなが")
      post_event(follow_event)

      expect { post_event(follow_event(is_redelivery: true)) }.not_to change(User, :count)
      expect(client).to have_received(:reply_message_with_http_info).once
    end
  end

  describe "unfollow（ブロック）" do
    it "既存ユーザーの line_blocked を true にし、記録は削除せず、返信しない" do
      user = create(:user, line_user_id: line_user_id)
      workout = create(:workout, user: user)

      post_event(unfollow_event)

      expect(response).to have_http_status(:ok)
      expect(user.reload.line_blocked).to be true
      expect(Workout.exists?(workout.id)).to be true
      expect(client).not_to have_received(:reply_message_with_http_info)
    end

    it "未登録ユーザーの unfollow は何もせず 200 を返す" do
      expect { post_event(unfollow_event) }.not_to change(User, :count)
      expect(response).to have_http_status(:ok)
    end
  end
end
