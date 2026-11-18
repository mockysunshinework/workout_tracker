require "rails_helper"

# 10.6 postback（Quick Reply のボタン選択）の処理（SPEC 4.3.1(3)(4)・ボタン構成は 10.2 / 10.2b）。
# 完了条件の 8 ケース: 選択・新規登録・キャンセル・stale・期限切れ、別名確認の はい・いいえ・stale。
# LINE API（Reply）は LineBot のクライアントを差し替えてモックする（10.5 と同じ方式）。モックなので、
# 実物の LINE でボタンが出て postback が届くことは 12.1 の実機確認で確かめる
RSpec.describe "LINE Webhook: postback（候補の確定と別名確認）", type: :request do
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

  def text_event(text, webhook_event_id: "01MESSAGE00000000000000001")
    {
      type: "message", message: { type: "text", id: "468789577898262530", text: text, quoteToken: "q-token" },
      webhookEventId: webhook_event_id, deliveryContext: { isRedelivery: false },
      timestamp: 1_789_000_000_000, source: { type: "user", userId: line_user_id },
      replyToken: "reply-token-1", mode: "active"
    }
  end

  def postback_event(data, webhook_event_id: "01POSTBACK0000000000000001", is_redelivery: false)
    {
      type: "postback", postback: { data: data },
      webhookEventId: webhook_event_id, deliveryContext: { isRedelivery: is_redelivery },
      timestamp: 1_789_000_000_000, source: { type: "user", userId: line_user_id },
      replyToken: "reply-token-2", mode: "active"
    }
  end

  # 送ろうとした返信メッセージ（各 1 件目）を送信順に返す
  def replied_messages
    messages = []
    expect(client).to have_received(:reply_message_with_http_info).at_least(:once) do |reply_message_request:|
      messages << reply_message_request.messages.first
    end
    messages
  end

  def last_reply
    replied_messages.last
  end

  # 「ベンチ60/5/3」を送って保留を作り、その保留を返す
  def hold_bench
    post_event(text_event("ベンチ60/5/3"))
    PendingWorkoutEntry.sole
  end

  describe "候補の選択（choose）" do
    it "保留していた記録を選んだ種目で保存し、保留を削除して、エコーバックの末尾に別名確認と はい／いいえ を付ける" do
      pending = hold_bench

      expect { post_event(postback_event("action=choose&pending_id=#{pending.id}&exercise_id=#{bench.id}")) }
        .to change(WorkoutSet, :count).by(3).and change(PendingWorkoutEntry, :count).by(-1)

      expect(response).to have_http_status(:ok)
      sets = user.workouts.sole.workout_sets.order(:set_number)
      expect(sets.map { |s| [ s.exercise, s.set_number, s.weight_kg, s.reps ] }).to eq [ [ bench, 1, 60, 5 ], [ bench, 2, 60, 5 ], [ bench, 3, 60, 5 ] ]

      alias_record = user.exercise_aliases.sole
      expect(alias_record).to have_attributes(alias: "ベンチ", exercise: bench, confirmed: false)

      message = last_reply
      expect(message.text).to include("の記録を保存しました").and include("ベンチプレス 60kg×5回×3セット")
      expect(message.text).to end_with("今後「ベンチ」はベンチプレスとして記録しますか？")
      actions = message.quick_reply.items.map(&:action)
      expect(actions.map(&:label)).to eq %w[はい いいえ]
      expect(actions.map(&:data)).to eq [ "action=alias_confirm&alias_id=#{alias_record.id}", "action=alias_decline&alias_id=#{alias_record.id}" ]
    end

    it "再送（同一 webhookEventId）では二重保存も再返信もしない" do
      pending = hold_bench
      data = "action=choose&pending_id=#{pending.id}&exercise_id=#{bench.id}"
      post_event(postback_event(data))

      expect { post_event(postback_event(data, is_redelivery: true)) }.not_to change(WorkoutSet, :count)

      expect(response).to have_http_status(:ok)
      expect(client).to have_received(:reply_message_with_http_info).twice # 候補提示 + 保存のエコーバック
    end
  end

  describe "新規種目として登録（create）" do
    it "入力名で独自種目を作って保存し、別名確認は付けない" do
      post_event(text_event("ランジ20/10"))
      pending = PendingWorkoutEntry.sole

      expect { post_event(postback_event("action=create&pending_id=#{pending.id}")) }
        .to change { user.exercises.count }.by(1).and change(WorkoutSet, :count).by(1).and change(PendingWorkoutEntry, :count).by(-1)

      lunge = user.exercises.sole
      expect(lunge.name).to eq "ランジ"
      expect(WorkoutSet.sole).to have_attributes(exercise: lunge, weight_kg: 20, reps: 10)
      expect(ExerciseAlias.count).to eq 0

      message = last_reply
      expect(message.text).to include("ランジ 20kg×10回×1セット")
      expect(message.text).not_to include("今後")
      expect(message.quick_reply).to be_nil
    end
  end

  describe "キャンセル（cancel）" do
    it "保留全体を破棄し、何も保存しない" do
      pending = hold_bench

      expect { post_event(postback_event("action=cancel&pending_id=#{pending.id}")) }
        .to change(PendingWorkoutEntry, :count).by(-1).and change(WorkoutSet, :count).by(0)

      expect(ExerciseAlias.count).to eq 0
      expect(last_reply.text).to eq LineMessages.cancelled
    end
  end

  describe "無効になった保留（stale postback）" do
    it "新しい入力で置き換えられた保留のボタンは何も保存せず、再入力を案内する" do
      old = hold_bench
      post_event(text_event("スクワ80/5", webhook_event_id: "01MESSAGE00000000000000002"))
      current = PendingWorkoutEntry.sole

      expect { post_event(postback_event("action=choose&pending_id=#{old.id}&exercise_id=#{bench.id}")) }
        .not_to change(WorkoutSet, :count)

      expect(response).to have_http_status(:ok)
      expect(last_reply.text).to eq LineMessages.stale_pending
      expect(PendingWorkoutEntry.sole.id).to eq current.id # 現在の保留は巻き込まない
    end

    it "解釈できない data も何もせず再入力を案内する" do
      post_event(postback_event("unexpected"))

      expect(response).to have_http_status(:ok)
      expect(last_reply.text).to eq LineMessages.stale_pending
    end
  end

  describe "期限切れの保留" do
    it "30 分を過ぎた保留のボタンは何も保存せず、保留を削除して再入力を案内する" do
      pending = hold_bench

      travel_to(31.minutes.from_now) do
        expect { post_event(postback_event("action=choose&pending_id=#{pending.id}&exercise_id=#{bench.id}")) }
          .to change(WorkoutSet, :count).by(0).and change(PendingWorkoutEntry, :count).by(-1)
      end

      expect(last_reply.text).to eq LineMessages.stale_pending
    end
  end

  describe "別名確認（alias_confirm / alias_decline）" do
    # 候補選択で保存した直後の状態（確認待ちの別名行がある）
    let!(:alias_record) { create(:exercise_alias, user: user, exercise: bench, alias: "ベンチ") }

    it "はい: 別名を確認済みにし、以後は同じ略称が候補提示なしで保存される" do
      post_event(postback_event("action=alias_confirm&alias_id=#{alias_record.id}"))

      expect(alias_record.reload.confirmed).to be true
      expect(last_reply.text).to eq "今後「ベンチ」はベンチプレスとして記録します。"

      expect { post_event(text_event("ベンチ70/3")) }.to change(WorkoutSet, :count).by(1)
      expect(PendingWorkoutEntry.count).to eq 0
      expect(WorkoutSet.sole.exercise).to eq bench
    end

    it "いいえ: 別名行を削除し（記憶しない）、次に同じ略称を送るとまた候補が出る" do
      expect { post_event(postback_event("action=alias_decline&alias_id=#{alias_record.id}")) }
        .to change(ExerciseAlias, :count).by(-1)

      expect(last_reply.text).to eq LineMessages.alias_declined(alias_record)

      expect { post_event(text_event("ベンチ70/3")) }.to change(PendingWorkoutEntry, :count).by(1)
    end

    it "stale: 該当する別名行が無ければ「この確認は無効になりました」と返す" do
      alias_record.destroy!

      post_event(postback_event("action=alias_confirm&alias_id=#{alias_record.id}"))
      post_event(postback_event("action=alias_decline&alias_id=#{alias_record.id}", webhook_event_id: "01POSTBACK0000000000000002"))

      expect(response).to have_http_status(:ok)
      expect(replied_messages.map(&:text)).to eq [ LineMessages.stale_alias, LineMessages.stale_alias ]
    end

    it "同じ略称で再び候補選択すると確認待ちの行が作り直され、古い [はい] は無効になる" do
      pending = hold_bench
      post_event(postback_event("action=choose&pending_id=#{pending.id}&exercise_id=#{incline.id}"))

      expect(ExerciseAlias.exists?(alias_record.id)).to be false
      expect(user.exercise_aliases.sole).to have_attributes(exercise: incline, confirmed: false)

      post_event(postback_event("action=alias_confirm&alias_id=#{alias_record.id}", webhook_event_id: "01POSTBACK0000000000000002"))

      expect(last_reply.text).to eq LineMessages.stale_alias
      expect(user.exercise_aliases.sole.confirmed).to be false
    end
  end
end
