require "rails_helper"

# 8.9 LINE API 呼び出しの薄いラッパー（SPEC 2.3 の例外 2 つ: Get profile / Reply）。
# SDK は 2xx 以外でも例外を投げず [body, status, headers] を返すため、status を見て扱う。
RSpec.describe LineBot do
  let(:client) { instance_double(Line::Bot::V2::MessagingApi::ApiClient) }

  before { allow(LineBot).to receive(:client).and_return(client) }

  describe ".fetch_display_name" do
    let(:line_user_id) { "U1234567890abcdef1234567890abcdef" }

    it "200 なら displayName を返す" do
      profile = Line::Bot::V2::MessagingApi::UserProfileResponse.new(display_name: "もとなが", user_id: line_user_id)
      allow(client).to receive(:get_profile_with_http_info).with(user_id: line_user_id).and_return([ profile, 200, {} ])

      expect(LineBot.fetch_display_name(line_user_id)).to eq "もとなが"
    end

    it "200 以外（未同意・ブロック中等の 404 など）なら nil を返し、警告ログを残す" do
      allow(client).to receive(:get_profile_with_http_info).and_return([ '{"message":"Not found"}', 404, {} ])
      allow(Rails.logger).to receive(:warn)

      expect(LineBot.fetch_display_name(line_user_id)).to be_nil
      expect(Rails.logger).to have_received(:warn).with(/profile.*404/i)
    end

    it "通信例外（タイムアウト等）でも nil を返し、例外を伝播させない" do
      allow(client).to receive(:get_profile_with_http_info).and_raise(Net::OpenTimeout)
      allow(Rails.logger).to receive(:warn)

      expect(LineBot.fetch_display_name(line_user_id)).to be_nil
      expect(Rails.logger).to have_received(:warn).with(/Net::OpenTimeout/)
    end
  end

  describe ".reply" do
    it "replyToken とテキスト 1 件で Reply API を呼び、200 なら true" do
      allow(client).to receive(:reply_message_with_http_info).and_return([ nil, 200, {} ])

      expect(LineBot.reply("token-1", "こんにちは")).to be true

      expect(client).to have_received(:reply_message_with_http_info) do |reply_message_request:|
        expect(reply_message_request.reply_token).to eq "token-1"
        expect(reply_message_request.messages.map(&:text)).to eq [ "こんにちは" ]
      end
    end

    it "200 以外（期限切れ token の 400 等）なら false を返し、警告ログを残す（リトライしない）" do
      allow(client).to receive(:reply_message_with_http_info).and_return([ nil, 400, {} ])
      allow(Rails.logger).to receive(:warn)

      expect(LineBot.reply("token-1", "こんにちは")).to be false
      expect(Rails.logger).to have_received(:warn).with(/reply.*400/i)
      expect(client).to have_received(:reply_message_with_http_info).once
    end

    it "通信例外でも false を返し、例外を伝播させない（返信の失敗を記録の保存に波及させない）" do
      allow(client).to receive(:reply_message_with_http_info).and_raise(Net::ReadTimeout)
      allow(Rails.logger).to receive(:warn)

      expect(LineBot.reply("token-1", "こんにちは")).to be false
      expect(Rails.logger).to have_received(:warn).with(/Net::ReadTimeout/)
    end
  end

  describe ".client" do
    it "Messaging API クライアントに短いタイムアウトを設定する（SPEC 2.3: 同期処理内の外部呼び出し）" do
      allow(LineBot).to receive(:client).and_call_original
      allow(LineBot).to receive(:channel_access_token).and_return("dummy")

      expect(Line::Bot::V2::MessagingApi::ApiClient).to receive(:new)
        .with(hash_including(http_options: hash_including(:open_timeout, :read_timeout)))
        .and_call_original

      LineBot.client
    end
  end
end
