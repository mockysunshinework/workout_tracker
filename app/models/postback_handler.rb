# LINE の postback（Quick Reply のボタン選択）を処理する（10.6・SPEC 4.3.1(3)(4)）:
#   choose / create / cancel       保留中の入力（PendingWorkoutEntry）の確定・新規登録・破棄
#   alias_confirm / alias_decline  候補選択で保存した直後の別名確認（ExerciseAlias）の はい／いいえ
# RecordMessageHandler と同じく、Webhook コントローラが ProcessedLineEvent.record_once のトランザクション内で
# 呼び、返信はコミット後に行う。LINE SDK の型は受け取らない（data の文字列だけ・SPEC 2.3 の境界）。
# data は外部入力なので、保留・種目・別名はすべて user を起点に引く（他ユーザーの id は「見つからない」になる）
module PostbackHandler
  # 処理結果。status ごとに使うフィールドが決まる:
  #   :saved             saved（エコーバック用）、exercise_alias（別名確認を付ける確認待ちの行。無ければ nil）
  #   :unknown_exercises pending / candidates（未知の種目がまだ残っている。次の候補を提示する）
  #   :invalid           invalid_messages（保存時の検証エラー。保留は破棄済み）
  #   :cancelled         保留を破棄した
  #   :stale_pending     保留が無い・期限切れ・置き換え済み、または data が解釈できない（再入力を案内する）
  #   :alias_confirmed / :alias_declined  exercise_alias（declined は削除済みの行。返信文の略称用）、
  #                      next_alias（同じ保存で作った次の確認待ち行。無ければ nil）
  #   :stale_alias       該当する確認待ちの別名行が無い
  Outcome = Data.define(:status, :saved, :exercise_alias, :next_alias, :pending, :candidates, :invalid_messages) do
    def initialize(status:, saved: nil, exercise_alias: nil, next_alias: nil, pending: nil, candidates: [], invalid_messages: [])
      super
    end
  end

  module_function

  def call(user:, data:)
    postback = LinePostback.decode(data)
    return Outcome.new(status: :stale_pending) if postback.nil?

    case postback.action
    when "alias_confirm", "alias_decline" then answer_alias(user, postback)
    else resolve_pending(user, postback)
    end
  end

  # 保留 id が一致しない（破棄・置き換え済み）か期限切れなら何もせず再入力を案内する。期限切れの行は削除する
  def resolve_pending(user, postback)
    pending = PendingWorkoutEntry.find_by(id: postback.ids["pending_id"], user: user)
    return Outcome.new(status: :stale_pending) if pending.nil?

    if pending.expired?
      pending.destroy!
      return Outcome.new(status: :stale_pending)
    end

    if postback.action == "cancel"
      pending.destroy!
      return Outcome.new(status: :cancelled)
    end

    # 確定と保存は savepoint（requires_new）で囲む。保存時の検証エラーで、作りかけの独自種目や保留の更新を
    # まとめて巻き戻すため（外側のトランザクション＝冪等 ID の登録は中断させない）
    PendingWorkoutEntry.transaction(requires_new: true) do
      if postback.action == "choose"
        exercise = Exercise.available_for(user).find_by(id: postback.ids["exercise_id"])
        next Outcome.new(status: :stale_pending) if exercise.nil?

        pending.resolve_current!(exercise)
      else
        # create: 入力名そのものを独自種目にする。種目を作るのは全件確定時（save_if_resolved）
        pending.resolve_current_as_new!
      end

      save_if_resolved(user, pending)
    end
  rescue ActiveRecord::RecordInvalid => e
    # 例: 重量が必要な種目を自重の入力に選んだ。ボタンでは直せないので保留を破棄し、理由を返して再入力してもらう。
    # savepoint が巻き戻った後なので、残るのは保留の破棄だけ（何も保存しない）
    pending.destroy!
    Outcome.new(status: :invalid, invalid_messages: [ RecordMessageHandler.invalid_message(e) ])
  end

  # 未知の種目が残っていれば次の候補を提示し（1 件ずつ順に確認: SPEC 4.3.1(3)）、全行確定していれば
  # 9.4 の保存に合流して保留を削除する（部分保存しない）。
  # 記録日は保留を受け付けた日（受信日・JST）。新規登録の種目と別名の確認待ち行は、この一括保存の時点で作る
  # （途中のキャンセル・期限切れでは何も残さない: SPEC 4.3.1(4)）
  def save_if_resolved(user, pending)
    if pending.current_unknown
      # 次の確認へ進むたびに保留の id を振り直し、前の確認のボタンを無効にする
      pending = pending.reissue!
      candidates = Exercise.candidates_for(user: user, name: pending.current_unknown["exercise_name"])
      return Outcome.new(status: :unknown_exercises, pending: pending, candidates: candidates)
    end

    pending.create_new_exercises!
    resolved = pending.resolved_entries
    if resolved.nil?
      pending.destroy!
      return Outcome.new(status: :stale_pending)
    end

    saved = RecordMessageHandler.save(user, pending.created_at.to_date, resolved)
    exercises = resolved.map(&:first).index_by(&:id)
    proposals = pending.alias_candidates.map { |alias_name, exercise_id| [ alias_name, exercises.fetch(exercise_id) ] }
    aliases = ExerciseAlias.replace_proposals!(user: user, proposals: proposals)
    pending.destroy!
    # 別名確認は 1 件ずつ。エコーバックには 1 件目だけを付け、残りは はい／いいえ の返信に乗せる（answer_alias）
    Outcome.new(status: :saved, saved: saved, exercise_alias: aliases.first)
  end

  # はい で確認済みにし、いいえ で削除する（記憶しない）。対象は確認待ちの行だけ:
  # 作り直された（id 再採番）・確認済み・削除済みの行に対するボタンは無効として扱う。
  # 同じ保存で作った確認待ち行がまだ残っていれば、次の 1 件を next_alias として返す（返信に次の確認を乗せる）。
  # 確認待ち行は直近の保存の分だけなので（ExerciseAlias.replace_proposals!）、残り＝同じ保存の分になる
  def answer_alias(user, postback)
    pending_aliases = user.exercise_aliases.where(confirmed: false)
    exercise_alias = pending_aliases.find_by(id: postback.ids["alias_id"])
    return Outcome.new(status: :stale_alias) if exercise_alias.nil?

    if postback.action == "alias_confirm"
      exercise_alias.update!(confirmed: true)
      status = :alias_confirmed
    else
      exercise_alias.destroy!
      status = :alias_declined
    end
    Outcome.new(status: status, exercise_alias: exercise_alias, next_alias: pending_aliases.order(:id).first)
  end

  private_class_method :resolve_pending, :save_if_resolved, :answer_alias
end
