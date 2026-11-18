require "rails_helper"

# 10.7 未知の種目が複数ある記録: 1 件ずつ候補確認 → 全件確定で一括保存 → 別名確認も 1 件ずつ（SPEC 4.3.1(3)(4)）。
# 途中でキャンセルしたら何も残さない。LINE API（Reply）はモック（10.5 / 10.6 と同じ方式）
RSpec.describe "LINE Webhook: 複数の未知種目の順次確認と一括保存", type: :request do
  let(:channel_secret) { "test-channel-secret" }
  let(:line_user_id) { "U1234567890abcdef1234567890abcdef" }
  let(:client) { instance_double(Line::Bot::V2::MessagingApi::ApiClient) }
  let!(:user) { create(:user, line_user_id: line_user_id) }
  let!(:bench) { create(:exercise, :preset, name: "ベンチプレス") }
  let!(:deadlift) { create(:exercise, :preset, name: "デッドリフト") }
  let!(:squat) { create(:exercise, :preset, name: "スクワット") }

  before do
    allow(LineBot).to receive(:channel_secret).and_return(channel_secret)
    allow(LineBot).to receive(:client).and_return(client)
    allow(client).to receive(:reply_message_with_http_info).and_return([ nil, 200, {} ])
    @event_number = 0
  end

  def post_event(event)
    content = { destination: "U0000", events: [ event ] }.to_json
    signature = Base64.strict_encode64(OpenSSL::HMAC.digest("SHA256", channel_secret, content))
    post webhooks_line_path, params: content,
         headers: { "CONTENT_TYPE" => "application/json", "X-Line-Signature" => signature }
  end

  def common_fields
    @event_number += 1
    {
      webhookEventId: format("01EVENT%019d", @event_number), deliveryContext: { isRedelivery: false },
      timestamp: 1_789_000_000_000, source: { type: "user", userId: line_user_id },
      replyToken: "reply-token-#{@event_number}", mode: "active"
    }
  end

  def send_text(text)
    post_event({ type: "message", message: { type: "text", id: "468789577898262530", text: text, quoteToken: "q-token" } }.merge(common_fields))
  end

  # 直前の返信に付いていた Quick Reply のうち、label が一致するボタンを押す
  def press(label)
    action = last_reply.quick_reply.items.map(&:action).find { |a| a.label == label }
    raise "button not found: #{label}" if action.nil?

    post_event({ type: "postback", postback: { data: action.data } }.merge(common_fields))
  end

  def last_reply
    messages = []
    expect(client).to have_received(:reply_message_with_http_info).at_least(:once) do |reply_message_request:|
      messages << reply_message_request.messages.first
    end
    messages.last
  end

  def button_labels
    last_reply.quick_reply.items.map { |item| item.action.label }
  end

  it "未知の 2 種目を 1 件ずつ確認し、全件確定した時点でまとめて保存して、別名確認も 1 件ずつ出す" do
    send_text("ベンチ60/5/2\nスクワット80/5\nデッド100/3")

    # 1 件目の確認。まだ何も保存しない
    expect(last_reply.text).to eq "「ベンチ」に一致する種目がありません。どれを記録しますか？"
    expect { press("ベンチプレス") }.to change(WorkoutSet, :count).by(0)

    # 2 件目の確認。1 件目を選んだだけでは保存も別名作成もしない
    expect(last_reply.text).to eq "「デッド」に一致する種目がありません。どれを記録しますか？"
    expect(button_labels).to eq [ "デッドリフト", "新規種目として登録", "キャンセル" ]
    expect(ExerciseAlias.count).to eq 0
    expect(PendingWorkoutEntry.count).to eq 1

    # 全件確定 → 一括保存
    expect { press("デッドリフト") }.to change(WorkoutSet, :count).by(4).and change(PendingWorkoutEntry, :count).by(-1)

    sets = user.workouts.sole.workout_sets.order(:id).map { |s| [ s.exercise, s.set_number, s.weight_kg, s.reps ] }
    expect(sets).to eq [ [ bench, 1, 60, 5 ], [ bench, 2, 60, 5 ], [ squat, 1, 80, 5 ], [ deadlift, 1, 100, 3 ] ]
    expect(user.exercise_aliases.order(:id).map { |a| [ a.alias, a.exercise, a.confirmed ] })
      .to eq [ [ "ベンチ", bench, false ], [ "デッド", deadlift, false ] ]

    # エコーバックには 1 件目の別名確認だけを付ける
    echo = last_reply.text
    expect(echo).to include("ベンチプレス 60kg×5回×2セット").and include("スクワット 80kg×5回×1セット").and include("デッドリフト 100kg×3回×1セット")
    expect(echo).to end_with("今後「ベンチ」はベンチプレスとして記録しますか？")
    expect(echo).not_to include("デッド」は")
    expect(button_labels).to eq %w[はい いいえ]

    # はい の返信に 2 件目の確認を乗せる
    press("はい")
    expect(last_reply.text).to eq "今後「ベンチ」はベンチプレスとして記録します。\n今後「デッド」はデッドリフトとして記録しますか？"
    expect(button_labels).to eq %w[はい いいえ]

    # 最後の確認への返信には、もう確認を付けない
    press("いいえ")
    expect(last_reply.text).to eq LineMessages.alias_declined(build(:exercise_alias, alias: "デッド"))
    expect(last_reply.quick_reply).to be_nil
    expect(user.exercise_aliases.map { |a| [ a.alias, a.confirmed ] }).to eq [ [ "ベンチ", true ] ]
  end

  it "途中でキャンセルすると、何も保存されない（記録・別名・新規登録しかけた種目・保留のいずれも残らない）" do
    send_text("ランジ20/10\nベンチ60/5")

    press("新規種目として登録") # 1 件目: ランジを新規登録すると答える
    expect(last_reply.text).to eq "「ベンチ」に一致する種目がありません。どれを記録しますか？"

    press("キャンセル") # 2 件目の確認でキャンセル

    expect(last_reply.text).to eq LineMessages.cancelled
    expect(WorkoutSet.count).to eq 0
    expect(Workout.count).to eq 0
    expect(ExerciseAlias.count).to eq 0
    expect(user.exercises.count).to eq 0
    expect(PendingWorkoutEntry.count).to eq 0
  end

  it "別名確認を無視して次の記録を送ると、残りの確認は出ない" do
    send_text("ベンチ60/5\nデッド100/3")
    press("ベンチプレス")
    press("デッドリフト") # 一括保存。エコーバックに 1 件目の確認が付く

    send_text("スクワット80/5") # 確認を無視して次の記録

    expect(last_reply.text).to include("スクワット 80kg×5回×1セット")
    expect(last_reply.text).not_to include("今後")
    expect(last_reply.quick_reply).to be_nil
    expect(user.exercise_aliases.where(confirmed: true).count).to eq 0
  end
end
