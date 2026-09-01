require "rails_helper"

# 7.4 LINE Webhook エンドポイントと署名検証（SPEC 4.2.4 / 8 章）。
# 署名はスタブせず実際の HMAC-SHA256 で計算し、検証ロジックそのものを通す。
RSpec.describe "LINE Webhook", type: :request do
  let(:channel_secret) { "test-channel-secret" }
  let(:body) { { destination: "U0000", events: [] }.to_json } # LINE からのHTTPリクエストの body部分

  before do
    allow(LineBot).to receive(:channel_secret).and_return(channel_secret) # LineBotモジュールのchannel_secretメソッドの返り値をlet(:channel_secret)で定義した値にする
  end

  # test 環境は CSRF 保護が既定で無効のため、有効化した状態で全 example を実行する。
  # これにより「CSRF 除外が本エンドポイントに効いていること」まで検証できる。
  around do |example|
    original = ActionController::Base.allow_forgery_protection # test 環境の Rails 設定では false が既定（RSpec ではなく環境設定が決めている）
    ActionController::Base.allow_forgery_protection = true
    example.run
  ensure
    ActionController::Base.allow_forgery_protection = original
  end

  def post_webhook(content, signature:)
    headers = { "CONTENT_TYPE" => "application/json" }
    headers["X-Line-Signature"] = signature if signature
    post webhooks_line_path, params: content, headers: headers
  end

  # Specで署名を作成する
  def signature_for(content)
    Base64.strict_encode64(OpenSSL::HMAC.digest("SHA256", channel_secret, content))
  end

  describe "POST /webhooks/line" do
    it "正しい署名なら 200 を返す（未ログイン・CSRF トークンなしで受理される）" do
      post_webhook(body, signature: signature_for(body))

      expect(response).to have_http_status(:ok)
    end

    it "署名が本文と一致しなければ 400 を返す（本文改ざんの拒否）" do
      post_webhook(body, signature: signature_for("tampered-body"))

      expect(response).to have_http_status(:bad_request)
    end

    it "署名ヘッダがなければ 400 を返す" do
      post_webhook(body, signature: nil)

      expect(response).to have_http_status(:bad_request)
    end

    it "誤ったシークレットで計算された署名は 400 を返す" do
      wrong = Base64.strict_encode64(OpenSSL::HMAC.digest("SHA256", "wrong-secret", body))

      post_webhook(body, signature: wrong)

      expect(response).to have_http_status(:bad_request)
    end
  end

  # follow イベント 1 件を含む Webhook 本文（冪等性・エラー分類の spec で共用）
  def webhook_body(webhook_event_id:)
    {
      destination: "U0000",
      events: [
        {
          type: "follow",
          follow: { isUnblocked: false },
          webhookEventId: webhook_event_id,
          deliveryContext: { isRedelivery: false },
          timestamp: 1_756_600_000_000,
          source: { type: "user", userId: "U1234567890abcdef1234567890abcdef" },
          replyToken: "dummy-reply-token",
          mode: "active"
        }
      ]
    }.to_json
  end

  describe "冪等性（webhookEventId の重複排除・SPEC 4.2.4）" do
    it "同一イベントを 2 回受信しても処理は 1 回で、どちらも 200 を返す（再送のスキップ）" do
      content = webhook_body(webhook_event_id: "01FZ74A0TDDPYRVKNK77XKC3ZR")

      2.times { post_webhook(content, signature: signature_for(content)) }

      expect(response).to have_http_status(:ok)
      expect(ProcessedLineEvent.where(webhook_event_id: "01FZ74A0TDDPYRVKNK77XKC3ZR").count).to eq 1
    end

    it "イベント ID が異なれば別イベントとして記録される" do
      first = webhook_body(webhook_event_id: "01FZ74A0TDDPYRVKNK77XKC3ZR")
      second = webhook_body(webhook_event_id: "01FZ74A0TDDPYRVKNK77XKC3ZS")

      post_webhook(first, signature: signature_for(first))
      post_webhook(second, signature: signature_for(second))

      expect(ProcessedLineEvent.count).to eq 2
    end

    it "events が空の Webhook（検証ボタン相当）は何も記録せず 200 を返す" do
      post_webhook(body, signature: signature_for(body))

      expect(response).to have_http_status(:ok)
      expect(ProcessedLineEvent.count).to eq 0
    end
  end

  describe "エラー分類応答（SPEC 4.2.4: 署名不正=400 / 業務エラー相当=200 / 一時障害=500）" do
    # test 環境の show_exceptions = :rescuable では未 rescue 例外が spec 内で raise される。
    # 「本番で 500 応答になる」ことをステータスとして検証するため :all に切り替える
    around do |example|
      original = Rails.application.env_config["action_dispatch.show_exceptions"]
      Rails.application.env_config["action_dispatch.show_exceptions"] = :all
      example.run
    ensure
      Rails.application.env_config["action_dispatch.show_exceptions"] = original
    end

    it "正署名でも本文が壊れた JSON なら 200 を返す（再送で回復しない・返信先もないため受領扱い）" do
      content = "{broken json"

      post_webhook(content, signature: signature_for(content))

      expect(response).to have_http_status(:ok)
    end

    it "正署名でも本文が Webhook 形式でない JSON なら 200 を返す" do
      content = "{}"

      post_webhook(content, signature: signature_for(content))

      expect(response).to have_http_status(:ok)
      expect(ProcessedLineEvent.count).to eq 0
    end

    it "業務処理中の DB 例外は rescue されず 500 になる（LINE の再送でリカバリさせる）" do
      allow(ProcessedLineEvent).to receive(:record_once)
        .and_raise(ActiveRecord::ConnectionNotEstablished)
      content = webhook_body(webhook_event_id: "01FZ74A0TDDPYRVKNK77XKC3ZR")

      post_webhook(content, signature: signature_for(content))

      expect(response).to have_http_status(:internal_server_error)
    end

    # 署名不正 = 400 は「POST /webhooks/line」の describe で検証済み
  end

  describe "他エンドポイントの保護が維持されていること" do
    it "Webhook 以外では CSRF 保護が引き続き有効（トークンなし POST は 422）" do
      user = create(:user)
      sign_in user

      post exercises_path, params: { exercise: { name: "CSRF テスト" } }

      # test 環境は show_exceptions = :rescuable のため、InvalidAuthenticityToken は
      # 例外ではなく 422 応答に変換される
      expect(response).to have_http_status(:unprocessable_content)
      expect(Exercise.exists?(name: "CSRF テスト")).to be false
    end
  end
end
