# LINE 記録入力の処理フロー（plan.md 7 章〜9.4 時点）

LINE のトークに `ベンチプレス60/5/3` と送ってから、DB に保存されてエコーバックが返るまでの流れを整理する。
対象は 2026-09-29 時点（PR #69 マージ後）の実装。仕様書の該当節は各所に付記する。

- 9.5（エラー応答）・10 章（種目候補提案）・11 章（コマンド）は未実装。現状の「受領だけして何も返さない」分岐がそれらの置き場所になる
- 図は Mermaid。GitHub 上でそのまま描画される

---

## 1. 全体像

```mermaid
flowchart LR
    U["LINE ユーザー"] -- "ベンチプレス60/5/3" --> L["LINE プラットフォーム"]
    L -- "POST /webhooks/line (署名付き JSON)" --> C["LineWebhooksController"]
    C --> H["RecordMessageHandler"]
    H --> P["RecordMessageParser<br/>(9.2 パース)"]
    H --> E["Exercise.find_exact_match<br/>(9.3 種目照合)"]
    H --> W["Workout / WorkoutSet<br/>(9.4 保存)"]
    C -- "LineMessages.recorded" --> R["LineBot.reply"]
    R -- "Reply API" --> L
    L -- "エコーバック" --> U
```

役割分担（仕様書 2.3「ドメイン層に LINE SDK の型を渡さない」に従う）:

| 層 | ファイル | 責務 | plan |
|---|---|---|---|
| 受信 | `app/controllers/line_webhooks_controller.rb` | 署名検証・イベント振り分け・冪等性・返信の呼び出し。SDK の型はここで止める | 7.4〜7.6, 8.9, 9.4 |
| LINE API | `app/models/line_bot.rb` | SDK クライアント、Get profile、Reply（短いタイムアウト・失敗はログのみ） | 7.3, 8.9 |
| 冪等性 | `app/models/processed_line_event.rb` | `webhookEventId` の登録と業務処理を同一トランザクションで実行 | 7.5 |
| 処理 | `app/models/record_message_handler.rb` | パース → 照合 → 保存をつなぎ、結果を `Outcome` で返す | 9.4 |
| パース | `app/models/record_message_parser.rb` | 短縮記法の文字列を「種目名＋(重量, 回数, セット数)」に変換。DB に触れない | 9.2 |
| 照合 | `app/models/exercise.rb` `app/models/exercise_name_normalizer.rb` | 正規化した名前の完全一致（ユーザー独自 → プリセット） | 3.3, 9.3 |
| 保存 | `app/models/workout.rb` `app/models/workout_set.rb` | 当日 workout の取得/作成、セットの採番と一括追記 | 4.3〜4.4, 9.4 |
| 文面 | `app/models/line_messages.rb` | 挨拶・入力案内・エコーバックの文言 | 8.9, 9.4 |

---

## 2. 時系列（正常系: 記録が保存されるまで）

```mermaid
sequenceDiagram
    autonumber
    participant LINE as LINE プラットフォーム
    participant C as LineWebhooksController
    participant PLE as ProcessedLineEvent
    participant H as RecordMessageHandler
    participant P as RecordMessageParser
    participant EX as Exercise
    participant W as Workout
    participant DB as PostgreSQL
    participant Bot as LineBot

    LINE->>C: POST /webhooks/line (X-Line-Signature + JSON)
    C->>C: 署名検証 (SDK WebhookParser)。不正なら 400
    C->>C: イベント種別で振り分け → message (テキスト)
    C->>DB: User.find_by(line_user_id)
    C->>PLE: record_once(webhookEventId) { ... }
    activate PLE
    Note over PLE,DB: ここから 1 つの DB トランザクション
    PLE->>DB: INSERT processed_line_events (unique)
    PLE->>H: call(user:, text:, performed_on: Date.current)
    H->>P: call(text)
    P-->>H: Result(entries: [種目名 + グループ列])
    H->>EX: find_exact_match(user:, name:) を行ごとに
    EX-->>H: Exercise (独自 → プリセットの順)
    Note over H,DB: savepoint (requires_new: true)
    H->>W: find_or_create_for_day!(user:, performed_on:)
    W->>DB: SELECT / INSERT workouts
    H->>W: append_sets!(exercise:, sets:) を種目ごとに
    W->>DB: SELECT ... FOR UPDATE (workout 行ロック)
    W->>DB: INSERT workout_sets (set_number は最大+1 から連番)
    H-->>PLE: Outcome(status: :saved, saved: ...)
    PLE->>DB: COMMIT
    deactivate PLE
    C->>Bot: reply(replyToken, LineMessages.recorded(saved))
    Bot->>LINE: Reply API (接続 3 秒 / 読み取り 5 秒)
    C-->>LINE: 200
```

押さえどころ:

- **返信は COMMIT の後**（仕様書 2.3）。返信に失敗しても記録は残る。逆に保存に失敗したら返信しない
- **再送（同じ `webhookEventId`）は 6 の INSERT が unique 制約で失敗し、ブロックが実行されない**ので二重保存も再返信もない（仕様書 4.2.4）
- 業務処理中の想定外の例外は rescue しない → 500 → LINE が再送 → 冪等 ID ごとロールバックされているのでやり直せる

---

## 3. 分岐（コントローラから handler まで）

```mermaid
flowchart TD
    A["POST /webhooks/line"] --> B{"署名ヘッダあり かつ<br/>署名一致?"}
    B -- いいえ --> B400["400 (再送されても失敗する)"]
    B -- はい --> Cp{"本文を Webhook として<br/>解釈できる?"}
    Cp -- いいえ --> C200["200 (ログのみ。返信先がない)"]
    Cp -- はい --> D{"イベント種別"}
    D -- follow --> F["User 作成 or 復帰<br/>挨拶＋入力案内を返信 (8.9)"]
    D -- unfollow --> UF["line_blocked = true (8.9)"]
    D -- "postback (未実装・10 章)" --> REC["冪等 ID だけ登録して受領"]
    D -- message --> M{"テキスト?"}
    M -- "いいえ (スタンプ等)" --> REC
    M -- はい --> U{"User あり?"}
    U -- "いいえ (9.5 で自己修復)" --> REC
    U -- はい --> H["record_once の中で<br/>RecordMessageHandler.call"]
    H --> S{"Outcome.status"}
    S -- ":saved" --> RP["コミット後に<br/>エコーバックを Reply"]
    S -- ":parse_failed (返信は 9.5)" --> NOREPLY["受領のみ (返信なし)"]
    S -- ":unknown_exercises (候補提案は 10 章)" --> NOREPLY
    S -- ":invalid (返信は 9.5)" --> NOREPLY
```

- `:parse_failed` `:unknown_exercises` `:invalid` のいずれも **何も保存しない**（仕様書 4.2.3「部分保存しない」）。複数行のうち 1 行でも該当したら全行が対象
- 上の 3 つは冪等 ID の登録だけはコミットされる。再送されても同じ結果になる「業務エラー」（4.2.4）なので 200 でよい

---

## 4. RecordMessageHandler の中身

```mermaid
flowchart TD
    IN["text"] --> P["RecordMessageParser.call"]
    P --> P1{"success?"}
    P1 -- いいえ --> OUT1["Outcome :parse_failed<br/>parse_result に行番号と理由"]
    P1 -- はい --> R["行ごとに Exercise.find_exact_match"]
    R --> R1{"全行 解決?"}
    R1 -- いいえ --> OUT2["Outcome :unknown_exercises<br/>unknown_names (初出順・重複なし)"]
    R1 -- はい --> G["同じ種目の行をまとめる<br/>(初出の順・グループは行の順)"]
    G --> T["Workout.transaction(requires_new: true)"]
    T --> W1["Workout.find_or_create_for_day!"]
    W1 --> W2["種目ごとに append_sets!<br/>(グループを sets 数に展開)"]
    W2 --> W3{"全件 保存できた?"}
    W3 -- "いいえ (RecordInvalid)" --> RB["savepoint を巻き戻す<br/>(作りかけの workout・セットだけ消える)"]
    RB --> OUT3["Outcome :invalid<br/>invalid_messages"]
    W3 -- はい --> CNT["当日のセット数を種目ごとに集計"]
    CNT --> OUT4["Outcome :saved<br/>Saved(performed_on, entries, total_set_count)"]
```

入力 → 出力の対応例:

| 入力（1 メッセージ） | パース結果 | 保存されるセット | エコーバック |
|---|---|---|---|
| `ベンチプレス60/5/3` | ベンチプレス [60×5 ×3] | set 1〜3: 60kg×5 | `ベンチプレス 60kg×5回×3セット（本日 計3セット）` |
| `ベンチプレス60/5/2 65/5` | ベンチプレス [60×5 ×2, 65×5 ×1] | set 1,2: 60×5 / set 3: 65×5 | `ベンチプレス 60kg×5回×2セット / 65kg×5回×1セット（本日 計3セット）` |
| `懸垂/10/3` | 懸垂 [自重×10 ×3] | set 1〜3: NULL×10 | `懸垂 自重×10回×3セット（本日 計3セット）` |
| `ベンチプレス60/5`<br/>`懸垂/10/2`<br/>`ベンチプレス70/3` | 3 行 → 種目ごとにまとめる | ベンチ set 1: 60×5, set 2: 70×3 / 懸垂 set 1,2 | 1 行に並べた場合と同じ表示（PR #69 レビュー対応） |
| 同日 2 通目 `ベンチプレス70/3`（既に 3 セットあり） | ベンチプレス [70×3 ×1] | set 4: 70×3（採番が続く） | `ベンチプレス 70kg×3回×1セット（本日 計4セット）` |
| `ベンチ 60 5 3`（旧記法） | 失敗 `:missing_group` | なし | なし（9.5 で案内を返す） |
| `ベンチ60/5`（プリセットに無い略称） | 解決できず | なし | なし（10 章で候補提案） |
| `ベンチプレス/10/3`（重量必須の種目に自重） | パースは成功 → 保存で検証エラー | なし | なし（9.5 で案内を返す） |

エコーバックの決め値（9.4）: グループは合算せず個別に列挙する（`懸垂/10 /3` のような打ち間違いが見えるように）。種目ごとの「本日 計 N セット」は今回分を含む当日累計。末尾に全種目の合計

---

## 5. データとトランザクション境界

```mermaid
erDiagram
    users ||--o{ workouts : "1 日 1 件 (user_id, performed_on) unique"
    users ||--o{ exercises : "独自種目 (user_id NULL はプリセット)"
    workouts ||--o{ workout_sets : "セット"
    exercises ||--o{ workout_sets : "種目"
    processed_line_events {
        string webhook_event_id "unique"
        datetime received_at
    }
    workouts {
        date performed_on "受信日 (JST)"
    }
    workout_sets {
        decimal weight_kg "NULL = 自重"
        int reps
        int set_number "同一 workout x 種目で連番 (unique)"
    }
    exercises {
        string name "表示名"
        string normalized_name "照合用 (NFKC/カナ/小文字)"
        bool bodyweight "true なら重量省略可"
    }
```

```mermaid
flowchart TB
    subgraph OUTER["record_once のトランザクション (業務処理の単位)"]
        E1["INSERT processed_line_events"]
        subgraph INNER["savepoint (requires_new: true)"]
            S1["workouts の取得/作成"]
            S2["workout_sets の INSERT (行ロック下で採番)"]
        end
    end
    E1 --> INNER
    INNER -- "RecordInvalid → ここだけ巻き戻す" --> KEEP["冪等 ID の登録は残す → :invalid で 200"]
    OUTER -- "想定外の例外 → 全部巻き戻す" --> RETRY["500 → LINE が再送 → やり直し"]
```

- 記録日は `Date.current`。`config.time_zone = "Tokyo"` なので JST の日付（仕様書 4.2.2。多国展開時は `users.time_zone` へ移行: 10 章 #18）
- 採番は `SELECT ... FOR UPDATE` で workout 行をロックして「最大 set_number + 1」から振る（4.4 の決定）。LINE と Web の同時入力でも重複しない
- 当日 workout の作成が別処理と競合した場合は検索し直す（`find_or_create_for_day!`）。500 にはしない

---

## 6. テストの見方（どこまでが本物で、どこがモックか）

```mermaid
flowchart LR
    subgraph SPEC["spec/requests/line_record_message_spec.rb"]
        J["post_event: LINE と同じ形の JSON を組み立て<br/>署名は本物の HMAC-SHA256 で計算"]
        D["instance_double(ApiClient)<br/>reply_message_with_http_info を差し替え<br/>= 外向き HTTP だけが偽物"]
    end
    J --> C["controller → SDK parse → handler → DB<br/>(すべて本物・テスト DB)"]
    C --> D
    D --> A["replied_texts で『送ろうとした文面』を検証"]
```

| spec | 検証する範囲 | モック |
|---|---|---|
| `spec/models/record_message_parser_spec.rb` | 文字列 → 構造（ケース表 A1〜A17 / R1〜R14） | なし（DB も使わない） |
| `spec/models/exercise_spec.rb`（`.find_exact_match`） | 正規化名の完全一致・独自優先・他ユーザー遮断 | なし |
| `spec/models/workout_spec.rb`（`.find_or_create_for_day!` / `#append_sets!`） | 当日 workout の取得/作成・採番の継続・全件巻き戻し | 競合再現のため `find_by` だけ stub |
| `spec/models/record_message_handler_spec.rb` | 4 つの Outcome と「何も保存しない」、savepoint と外側トランザクションの関係 | なし |
| `spec/models/line_messages_spec.rb`（`.recorded`） | エコーバックの文面 | なし |
| `spec/requests/line_record_message_spec.rb` | Webhook 受信 → 保存 → 返信の通し。JST の日付・再送・コミット後の返信 | LINE への HTTP（Reply）のみ |
| `spec/requests/line_webhooks_spec.rb` / `line_follow_unfollow_spec.rb` | 署名・冪等性・エラー分類 / follow・unfollow | LINE への HTTP（Get profile / Reply）のみ |

実物の LINE で同じ流れを確認するのは 12.1（ngrok で開発環境を公開・7.7 の再送設定もここで実施）。request spec の `text_event` が組み立てている JSON は、そのとき実際に届く Webhook 本文と同じ形なので、ログと見比べると対応が取れる

---

## 7. これからの項目との接点

| 項目 | 現状の置き場所 | 追加するもの |
|---|---|---|
| 9.5 エラー応答 | `handle_message` の `:parse_failed` / `:invalid` 分岐、User なしの分岐 | 失敗行＋入力例の返信、`User.find_or_create_from_line!` による自己修復、その他テキストへのヘルプ |
| 9.6 Reply 呼び出し条件 | `LineBot.reply`（タイムアウト・失敗時ログのみは実装済み） | 失敗時に記録が残ることの spec を通しで確認 |
| 10 章 候補提案 | `:unknown_exercises` 分岐 | 候補検索・`pending_workout_entries`・Quick Reply・postback。確定後は 9.4 の保存に合流 |
| 11 章 コマンド | `handle_message` の先頭 | `ヘルプ` `今日` `履歴` の判定を handler より前に置く |
