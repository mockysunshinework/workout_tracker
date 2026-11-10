# Webhook 冪等性の担保（SPEC 4.2.4 / 4.5）。webhookEventId 単位で重複排除する。
class ProcessedLineEvent < ApplicationRecord
  # 未処理のイベントなら、ID 登録と業務処理（ブロック）を同一トランザクションで実行して true を返す。
  # 登録済みならブロックを実行せず false を返す（再送・並行受信のスキップ）。
  # ブロックの例外は握りつぶさず伝播させる: 登録ごと巻き戻ることで、LINE の再送（4.2.4 の
  # 500 → redelivery）で業務処理をやり直せる。
  # 「登録済み」の判定は ID の INSERT だけを savepoint で囲んで行う。ブロック側で起きた RecordNotUnique
  # （例: 保留 pending_workout_entries の並行作成）まで「イベント重複」と取り違えて 200 で握りつぶさないため
  # （10.5 で修正。以前はメソッド全体で rescue していた）
  def self.record_once(webhook_event_id)
    transaction do
      next false unless register(webhook_event_id)

      yield if block_given?
      true
    end
  end

  # ID を登録できたら true。unique 制約に当たったら（登録済み）false。savepoint 内で INSERT するので、
  # 違反しても外側のトランザクションは中断しない
  def self.register(webhook_event_id)
    transaction(requires_new: true) do
      create!(webhook_event_id: webhook_event_id, received_at: Time.current)
    end
    true
  rescue ActiveRecord::RecordNotUnique
    false
  end
  private_class_method :register
end
