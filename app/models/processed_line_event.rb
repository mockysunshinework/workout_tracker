# Webhook 冪等性の担保（SPEC 4.2.4 / 4.5）。webhookEventId 単位で重複排除する。
class ProcessedLineEvent < ApplicationRecord
  # 未処理のイベントなら、ID 登録と業務処理（ブロック）を同一トランザクションで実行して true を返す。
  # 登録済みならブロックを実行せず false を返す（再送・並行受信のスキップ）。
  # ブロックの例外は握りつぶさず伝播させる: 登録ごと巻き戻ることで、LINE の再送（4.2.4 の
  # 500 → redelivery）で業務処理をやり直せる。
  def self.record_once(webhook_event_id)
    transaction do
      create!(webhook_event_id: webhook_event_id, received_at: Time.current)
      yield if block_given?
      true
    end
  rescue ActiveRecord::RecordNotUnique
    false
  end
end
