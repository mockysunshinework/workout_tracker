require "rails_helper"

# 7.5b Webhook 冪等性（SPEC 4.2.4）: イベント ID の登録と業務処理を同一トランザクションで行う
RSpec.describe ProcessedLineEvent do
  let(:event_id) { "01FZ74A0TDDPYRVKNK77XKC3ZR" }

  describe ".record_once" do
    it "未処理のイベントならブロックを実行し、ID を記録して true を返す" do
      executed = false

      result = described_class.record_once(event_id) { executed = true }

      expect(result).to be true
      expect(executed).to be true
      expect(described_class.exists?(webhook_event_id: event_id)).to be true
    end

    it "登録済みのイベントならブロックを実行せず false を返す（重複排除）" do
      described_class.record_once(event_id)
      executed = false

      result = described_class.record_once(event_id) { executed = true }

      expect(result).to be false
      expect(executed).to be false
      expect(described_class.where(webhook_event_id: event_id).count).to eq 1
    end

    it "ブロックが失敗したら ID 登録も巻き戻る（同一トランザクション＝再送でリカバリ可能）" do
      expect {
        described_class.record_once(event_id) { raise "business failure" }
      }.to raise_error(RuntimeError, "business failure")

      expect(described_class.exists?(webhook_event_id: event_id)).to be false
    end

    it "received_at が記録される" do
      described_class.record_once(event_id)

      expect(described_class.find_by(webhook_event_id: event_id).received_at).to be_present
    end
  end

  # 10.5 で判明: 業務処理（ブロック）側の一意制約違反を「イベント重複」と取り違えてはいけない。
  # 例: 保留（pending_workout_entries）の並行作成。4.2.4 の一時的な障害として 500 → 再送でやり直す
  describe "ブロック内の RecordNotUnique" do
    it "握りつぶさず伝播し、イベント ID の登録も巻き戻る" do
      expect {
        described_class.record_once("01EVENT0000000000000000009") do
          raise ActiveRecord::RecordNotUnique, "duplicate key value violates unique constraint \"index_pending_workout_entries_on_user_id\""
        end
      }.to raise_error(ActiveRecord::RecordNotUnique)

      expect(described_class.exists?(webhook_event_id: "01EVENT0000000000000000009")).to be false
    end
  end
end
