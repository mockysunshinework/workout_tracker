class CreateProcessedLineEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :processed_line_events do |t|
      t.string :webhook_event_id, null: false
      t.datetime :received_at, null: false

      t.timestamps
    end

    # Webhook 冪等性の担保（SPEC 4.2.4 / 4.5）。webhookEventId は ULID で再送時も不変（7.1 で確認）。
    add_index :processed_line_events, :webhook_event_id, unique: true
  end
end
