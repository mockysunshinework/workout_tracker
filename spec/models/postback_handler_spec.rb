require "rails_helper"

# 10.6 postback（Quick Reply のボタン選択）の処理（SPEC 4.3.1(3)(4)）。Webhook 経由の 8 ケースは
# spec/requests/line_postback_spec.rb。ここでは request では作りにくい条件と権限分離を検証する
RSpec.describe PostbackHandler, type: :model do
  let(:user) { create(:user) }
  let!(:bench) { create(:exercise, :preset, name: "ベンチプレス") }

  def lines(*rows)
    rows.each_with_index.map do |(name, exercise_id, weight), i|
      { "line_number" => i + 1, "exercise_name" => name, "exercise_id" => exercise_id,
        "groups" => [ { "weight_kg" => weight, "reps" => 5, "sets" => 1 } ] }
    end
  end

  def handle(action, user: self.user, **ids)
    described_class.call(user: user, data: LinePostback.encode(action: action, **ids))
  end

  describe "権限分離（他ユーザーの保留・種目・別名は扱えない）" do
    let(:other) { create(:user) }

    it "他ユーザーの保留 id では何もせず :stale_pending" do
      pending = create(:pending_workout_entry, user: other)

      expect(handle(:choose, pending_id: pending.id, exercise_id: bench.id).status).to eq :stale_pending
      expect(handle(:create, pending_id: pending.id).status).to eq :stale_pending
      expect(handle(:cancel, pending_id: pending.id).status).to eq :stale_pending
      expect(PendingWorkoutEntry.exists?(pending.id)).to be true
      expect(WorkoutSet.count).to eq 0
      expect(Exercise.where(user: [ user, other ]).count).to eq 0
    end

    it "他ユーザーの独自種目を choose しても保存せず :stale_pending（保留は残す）" do
      pending = create(:pending_workout_entry, user: user)
      others_exercise = create(:exercise, user: other, name: "他人の種目")

      expect(handle(:choose, pending_id: pending.id, exercise_id: others_exercise.id).status).to eq :stale_pending
      expect(WorkoutSet.count).to eq 0
      expect(pending.reload.current_unknown).to be_present
    end

    it "他ユーザーの別名 id では :stale_alias で、行は変わらない" do
      alias_record = create(:exercise_alias, user: other, exercise: bench, alias: "ベンチ")

      expect(handle(:alias_confirm, alias_id: alias_record.id).status).to eq :stale_alias
      expect(handle(:alias_decline, alias_id: alias_record.id).status).to eq :stale_alias
      expect(alias_record.reload.confirmed).to be false
    end
  end

  it "解釈できない data は :stale_pending" do
    expect(described_class.call(user: user, data: "garbage").status).to eq :stale_pending
  end

  it "記録日は保留を受け付けた日（受信日・JST）で、ボタンを押した日ではない" do
    pending = travel_to(Time.zone.local(2026, 11, 10, 23, 50)) { create(:pending_workout_entry, user: user) }

    outcome = travel_to(Time.zone.local(2026, 11, 11, 0, 5)) { handle(:choose, pending_id: pending.id, exercise_id: bench.id) }

    expect(outcome.status).to eq :saved
    expect(outcome.saved.performed_on).to eq Date.new(2026, 11, 10)
    expect(user.workouts.sole.performed_on).to eq Date.new(2026, 11, 10)
  end

  describe "新規種目として登録" do
    it "重量ありの入力は重量必須（bodyweight: false）の独自種目になる" do
      pending = create(:pending_workout_entry, user: user, parsed_lines: lines([ "ランジ", nil, "20.0" ]))

      expect(handle(:create, pending_id: pending.id).status).to eq :saved
      expect(user.exercises.sole).to have_attributes(name: "ランジ", bodyweight: false)
    end

    it "自重（重量なし）の入力は bodyweight: true の独自種目になり、そのまま保存できる" do
      pending = create(:pending_workout_entry, user: user, parsed_lines: lines([ "逆立ち腕立て", nil, nil ]))

      expect(handle(:create, pending_id: pending.id).status).to eq :saved
      expect(user.exercises.sole).to have_attributes(name: "逆立ち腕立て", bodyweight: true)
      expect(WorkoutSet.sole.weight_kg).to be_nil
    end
  end

  it "重量が必要な種目を自重の入力に選んだ場合は :invalid で何も保存せず、保留を破棄する" do
    pending = create(:pending_workout_entry, user: user, parsed_lines: lines([ "ベンチ", nil, nil ]))

    outcome = handle(:choose, pending_id: pending.id, exercise_id: bench.id)

    expect(outcome.status).to eq :invalid
    expect(outcome.invalid_messages.first).to include("ベンチプレス")
    expect(WorkoutSet.count).to eq 0
    expect(Workout.count).to eq 0
    expect(ExerciseAlias.count).to eq 0
    expect(PendingWorkoutEntry.exists?(pending.id)).to be false
  end

  # PR #92 レビュー所見 1: 新規登録を選んだ後で別の行が保存エラーになると、作った種目だけが残っていた
  it "新規登録を選んだ入力が保存エラーになった場合は、作りかけの種目も残さない" do
    # 1 行目は完全一致で解決済みだが、重量必須の種目に自重で入力されている（保存時に検証エラーになる）
    pending = create(:pending_workout_entry, user: user, parsed_lines: lines([ "ベンチプレス", bench.id, nil ], [ "ランジ", nil, "20.0" ]))

    outcome = handle(:create, pending_id: pending.id)

    expect(outcome.status).to eq :invalid
    expect(outcome.invalid_messages.first).to include("ベンチプレス")
    expect(user.exercises.count).to eq 0
    expect(WorkoutSet.count).to eq 0
    expect(Workout.count).to eq 0
    expect(PendingWorkoutEntry.exists?(pending.id)).to be false
  end

  it "保留中に解決済みの種目が削除されていた場合は :stale_pending で保留を破棄する" do
    mine = create(:exercise, user: user, name: "マイプレス")
    pending = create(:pending_workout_entry, user: user, parsed_lines: lines([ "マイプレス", mine.id, "40.0" ], [ "ベンチ", nil, "60.0" ]))
    mine.destroy!

    expect(handle(:choose, pending_id: pending.id, exercise_id: bench.id).status).to eq :stale_pending
    expect(WorkoutSet.count).to eq 0
    expect(PendingWorkoutEntry.exists?(pending.id)).to be false
  end

  it "未知の種目がまだ残っていれば保存せず、次の未知種目の候補を返す（順次確認の全体は 10.7）" do
    deadlift = create(:exercise, :preset, name: "デッドリフト")
    pending = create(:pending_workout_entry, user: user, parsed_lines: lines([ "ベンチ", nil, "60.0" ], [ "デッド", nil, "100.0" ]))

    outcome = handle(:choose, pending_id: pending.id, exercise_id: bench.id)

    expect(outcome.status).to eq :unknown_exercises
    expect(outcome.pending.current_unknown["exercise_name"]).to eq "デッド"
    expect(outcome.candidates).to eq [ deadlift ]
    expect(WorkoutSet.count).to eq 0
    expect(ExerciseAlias.count).to eq 0
  end

  # 10.7 順次確認。data は pending_id と exercise_id だけなので、確認が次へ進むたびに保留の id を振り直して
  # 前の確認のボタンを無効にする（置き換えと同じ「id 再採番」の方式: SPEC 4.3.1(3)）
  describe "順次確認で前の確認のボタンを押した場合" do
    let!(:deadlift) { create(:exercise, :preset, name: "デッドリフト") }
    let!(:pending) { create(:pending_workout_entry, user: user, parsed_lines: lines([ "ベンチ", nil, "60.0" ], [ "デッド", nil, "100.0" ])) }

    it "次の確認へ進むと保留の id が変わり、受付時刻と期限は変わらない" do
      outcome = handle(:choose, pending_id: pending.id, exercise_id: bench.id)

      expect(outcome.pending.id).not_to eq pending.id
      expect(PendingWorkoutEntry.where(user: user).sole).to eq outcome.pending
      expect(outcome.pending).to have_attributes(created_at: pending.created_at, expires_at: pending.expires_at)
    end

    it "1 件目の候補ボタンをもう一度押しても 2 件目の種目には適用されず、進行中の保留も壊さない" do
      current = handle(:choose, pending_id: pending.id, exercise_id: bench.id).pending

      outcome = handle(:choose, pending_id: pending.id, exercise_id: bench.id)

      expect(outcome.status).to eq :stale_pending
      expect(WorkoutSet.count).to eq 0
      expect(current.reload.current_unknown["exercise_name"]).to eq "デッド"
    end
  end

  describe "新規登録を選んだ後の途中キャンセル・期限切れ（10.7）" do
    let!(:pending) { create(:pending_workout_entry, user: user, parsed_lines: lines([ "ランジ", nil, "20.0" ], [ "ベンチ", nil, "60.0" ])) }

    it "新規登録を選んだ時点では種目を作らない（全件確定時にまとめて作る）" do
      outcome = nil
      expect { outcome = handle(:create, pending_id: pending.id) }.not_to change(Exercise, :count)

      expect(outcome.status).to eq :unknown_exercises
      expect(outcome.pending.current_unknown["exercise_name"]).to eq "ベンチ"
    end

    it "その後キャンセルすると、種目も記録も別名も残らない" do
      current = handle(:create, pending_id: pending.id).pending

      expect(handle(:cancel, pending_id: current.id).status).to eq :cancelled
      expect(user.exercises.count).to eq 0
      expect(WorkoutSet.count).to eq 0
      expect(ExerciseAlias.count).to eq 0
      expect(PendingWorkoutEntry.count).to eq 0
    end

    it "全件確定すると、新規登録の種目を作ってまとめて保存する" do
      current = handle(:create, pending_id: pending.id).pending

      outcome = handle(:choose, pending_id: current.id, exercise_id: bench.id)

      expect(outcome.status).to eq :saved
      lunge = user.exercises.sole
      expect(lunge.name).to eq "ランジ"
      expect(WorkoutSet.order(:id).map { |s| [ s.exercise, s.weight_kg ] }).to eq [ [ lunge, 20 ], [ bench, 60 ] ]
      expect(user.exercise_aliases.sole).to have_attributes(alias: "ベンチ", exercise: bench, confirmed: false)
    end
  end

  # 10.7 別名確認は 1 件ずつ: はい／いいえ の結果に、同じ保存で作った次の確認待ち行を添える
  describe "別名確認の順次提示" do
    let!(:deadlift) { create(:exercise, :preset, name: "デッドリフト") }
    let!(:first) { create(:exercise_alias, user: user, exercise: bench, alias: "ベンチ") }
    let!(:second) { create(:exercise_alias, user: user, exercise: deadlift, alias: "デッド") }

    it "はい の結果に次の確認待ち行を添える" do
      outcome = handle(:alias_confirm, alias_id: first.id)

      expect(outcome.status).to eq :alias_confirmed
      expect(outcome.next_alias).to eq second
    end

    it "いいえ の結果にも次の確認待ち行を添える" do
      outcome = handle(:alias_decline, alias_id: first.id)

      expect(outcome.status).to eq :alias_declined
      expect(outcome.next_alias).to eq second
    end

    it "最後の 1 件に答えたら次は無い" do
      handle(:alias_confirm, alias_id: first.id)

      expect(handle(:alias_decline, alias_id: second.id).next_alias).to be_nil
    end

    it "他ユーザーの確認待ち行は次の確認にしない" do
      second.destroy!
      create(:exercise_alias, exercise: deadlift, alias: "デッド")

      expect(handle(:alias_confirm, alias_id: first.id).next_alias).to be_nil
    end

    it "無視された以前の確認は、次に候補選択で保存した時点で消える（後から蒸し返さない）" do
      pending = create(:pending_workout_entry, user: user, parsed_lines: lines([ "インクラ", nil, "40.0" ]))
      incline = create(:exercise, :preset, name: "インクラインベンチプレス")

      outcome = handle(:choose, pending_id: pending.id, exercise_id: incline.id)

      expect(user.exercise_aliases.where(confirmed: false).sole).to eq outcome.exercise_alias
      expect(outcome.exercise_alias.alias).to eq "インクラ"
      expect(handle(:alias_confirm, alias_id: first.id).status).to eq :stale_alias
    end
  end

  it "同じ略称が確認済みの別名になっていた場合は別名確認を付けない" do
    create(:exercise_alias, :confirmed, user: user, exercise: bench, alias: "ベンチ")
    pending = create(:pending_workout_entry, user: user)

    outcome = handle(:choose, pending_id: pending.id, exercise_id: bench.id)

    expect(outcome.status).to eq :saved
    expect(outcome.exercise_alias).to be_nil
  end

  it "確認済みの別名に対する いいえ は :stale_alias で、別名を消さない" do
    confirmed = create(:exercise_alias, :confirmed, user: user, exercise: bench, alias: "ベンチ")

    expect(handle(:alias_decline, alias_id: confirmed.id).status).to eq :stale_alias
    expect(ExerciseAlias.exists?(confirmed.id)).to be true
  end
end
