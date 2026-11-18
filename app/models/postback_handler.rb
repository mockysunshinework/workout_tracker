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
  #   :alias_confirmed / :alias_declined  exercise_alias（declined は削除済みの行。返信文の略称用）
  #   :stale_alias       該当する確認待ちの別名行が無い
  Outcome = Data.define(:status, :saved, :exercise_alias, :pending, :candidates, :invalid_messages) do
    def initialize(status:, saved: nil, exercise_alias: nil, pending: nil, candidates: [], invalid_messages: [])
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

        pending.resolve_current!(exercise, chosen: true)
      else
        # create: 入力名そのものを独自種目にする。自重で入力されていれば重量を省略できる種目として作る
        # （重量必須で作ると、いま確定しようとしている自重の記録が保存できないため）
        exercise = user.exercises.create!(name: pending.current_unknown["exercise_name"], bodyweight: pending.current_unknown_bodyweight?)
        pending.resolve_current!(exercise, chosen: false)
      end

      save_if_resolved(user, pending)
    end
  rescue ActiveRecord::RecordInvalid => e
    # 例: 重量が必要な種目を自重の入力に選んだ。ボタンでは直せないので保留を破棄し、理由を返して再入力してもらう。
    # savepoint が巻き戻った後なので、残るのは保留の破棄だけ（何も保存しない）
    pending.destroy!
    Outcome.new(status: :invalid, invalid_messages: [ RecordMessageHandler.invalid_message(e) ])
  end

  # 未知の種目が残っていれば次の候補を提示し、全行確定していれば 9.4 の保存に合流して保留を削除する。
  # 記録日は保留を受け付けた日（受信日・JST）。別名の確認待ち行は保存の時点で作る（SPEC 4.3.1(4)）
  def save_if_resolved(user, pending)
    if (unknown = pending.current_unknown)
      candidates = Exercise.candidates_for(user: user, name: unknown["exercise_name"])
      return Outcome.new(status: :unknown_exercises, pending: pending, candidates: candidates)
    end

    resolved = pending.resolved_entries
    if resolved.nil?
      pending.destroy!
      return Outcome.new(status: :stale_pending)
    end

    saved = RecordMessageHandler.save(user, pending.created_at.to_date, resolved)
    exercises = resolved.map(&:first).index_by(&:id)
    aliases = pending.alias_candidates.filter_map do |alias_name, exercise_id|
      ExerciseAlias.propose!(user: user, alias_name: alias_name, exercise: exercises.fetch(exercise_id))
    end
    pending.destroy!
    Outcome.new(status: :saved, saved: saved, exercise_alias: aliases.first)
  end

  # はい で確認済みにし、いいえ で削除する（記憶しない）。対象は確認待ちの行だけ:
  # 作り直された（id 再採番）・確認済み・削除済みの行に対するボタンは無効として扱う
  def answer_alias(user, postback)
    exercise_alias = user.exercise_aliases.where(confirmed: false).find_by(id: postback.ids["alias_id"])
    return Outcome.new(status: :stale_alias) if exercise_alias.nil?

    if postback.action == "alias_confirm"
      exercise_alias.update!(confirmed: true)
      Outcome.new(status: :alias_confirmed, exercise_alias: exercise_alias)
    else
      exercise_alias.destroy!
      Outcome.new(status: :alias_declined, exercise_alias: exercise_alias)
    end
  end

  private_class_method :resolve_pending, :save_if_resolved, :answer_alias
end
