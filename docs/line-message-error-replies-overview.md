# LINE メッセージエラー応答 実装 Overview

この資料は、9.5「エラー応答の実装」の変更内容をレビュー・引き継ぎするための読み順をまとめたものです。

今回の主な変更は、LINE のテキストメッセージが正常な筋トレ記録ではなかった場合にも、ユーザーへ入力案内や失敗理由を返信することです。あわせて、follow イベントを受けていない LINE ユーザーからメッセージが届いた場合も、User を自己修復的に作成して通常処理へ進めるようにしています。

## Overview

実装したこと:

- パース失敗時に、失敗した行・理由・「全行未保存」であること・入力例を返信する
- 記録の形ではない通常テキストに、入力方法の案内を返信する
- 保存時の検証エラーに、保存できなかった理由と入力方法の案内を返信する
- follow 未受信の LINE ユーザーを `User.find_or_create_from_line!` で作成してから処理する
- Webhook の返信分岐を `Outcome` のステータス単位に整理する
- 上記の request/model spec を追加・更新する

重要な仕様判断:

- `RecordMessageParser` が失敗したとき、NFKC 正規化後の本文に `/` を含むなら `:parse_failed` とする
- `/` を含まない入力は `:unrecognized` とする
- 旧記法のような `ベンチプレス 60 5 3` は推測補正せず、`unrecognized` として入力案内だけを返す
- 1 行でもパース失敗があれば、成功している行も含めて全行保存しない
- 未知の種目は今回返信しない。候補提案は 10 章の範囲
- Reply API は DB コミット後に呼ぶ。返信失敗で保存をロールバックしない既存方針を維持する

## 最初に見るファイル

1. `app/controllers/line_webhooks_controller.rb`
   - LINE Webhook から見た今回の入口です。
   - `handle_message` で User 自己修復、冪等処理、記録処理、返信までの流れを確認できます。
   - `reply_text_for` が `Outcome` ごとの返信文を決めます。

2. `app/models/record_message_handler.rb`
   - ドメイン側の分岐の中心です。
   - パース結果を `:saved` / `:unrecognized` / `:parse_failed` / `:unknown_exercises` / `:invalid` に分類します。
   - `record_like?` が、今回追加した「記録を書こうとした失敗」と「その他テキスト」の境界です。

3. `app/models/line_messages.rb`
   - ユーザーへ返す文言の中心です。
   - `parse_failed` / `unrecognized` / `invalid` が今回追加された返信文です。
   - `PARSE_ERROR_REASONS` が parser の reason code を利用者向け文言に変換します。

## 必須理解箇所

### `LineWebhooksController#handle_message`

見るポイント:

- テキスト以外のメッセージは、従来どおり `ProcessedLineEvent.record_once` だけで受領する
- テキストメッセージでは `User.find_or_create_from_line!(line_user_id:, display_name: nil)` を先に呼ぶ
- `RecordMessageHandler.call` は `record_once` の中で 1 回だけ実行される
- `LineBot.reply` は `record_once` の外、つまり DB コミット後に呼ばれる
- 再送などで `record_once` のブロックが実行されない場合は `outcome` が nil のままなので返信しない

特に重要なリスク:

- User 作成を `record_once` の外に置いている点は意図的です。並行作成（初回メッセージと初回 LINE Login の同時接触）で unique 制約違反がトランザクション内で起きると PostgreSQL がそのトランザクションを中断し、`find_or_create_from_line!` の rescue 内の `find_by!` まで失敗して冪等イベント登録ごと巻き戻ってしまうためです。外に置けば `create!` 単体が巻き戻るだけで、既存行を返して続行できます。
- `display_name: nil` にしている点も意図的です。Get profile は follow 時だけ許可された外部呼び出しとして扱い、message 受信時には呼びません。作成される User はフォールバック名（`User::FALLBACK_NAME`）になり、次回の LINE Login（`update_name: true`）で更新されます。

### `RecordMessageHandler.call`

見るポイント:

- `RecordMessageParser.call(text)` が失敗したときだけ、`record_like?` で `:parse_failed` と `:unrecognized` を分ける
- parser が成功した後の未知種目や保存処理は、既存の「部分保存しない」方針を維持している
- `ActiveRecord::RecordInvalid` は `:invalid` に変換され、外側の冪等イベント登録は中断しない

必須の境界:

- `こんにちは` → `:unrecognized`
- `ベンチプレス 60 5 3` → `:unrecognized`
- `ベンチプレス60/` → `:parse_failed`
- `ベンチプレス60/5` と `こんにちは` の混在で片方が失敗 → `:parse_failed`、全行未保存

### `LineMessages.parse_failed`

見るポイント:

- 行単位のエラーは `N行目「元入力」: 理由` で返す
- 行数超過・空メッセージのようなメッセージ全体のエラーは行番号なしで返す
  - ただし Webhook 経由では、空メッセージは `/` を含まないため `record_like?` で `:unrecognized` に分類され、`parse_failed` には到達しません。実際にこの分岐へ来るのは行数超過（`too_many_lines`）です
- 返信文に `input_guide` を含める
- 「1 行でも失敗すると全行が未保存」と明示している

### `spec/requests/line_message_error_replies_spec.rb`

今回の振る舞いを最も外側から固定している spec です。

必ず見るケース:

- パース失敗時に成功行も含めて DB に保存しない
- その他テキストで入力案内を返信する
- 保存時の検証エラーで理由を返信する
- 返信 API が 400 を返しても Webhook は 200 を返す
- User 未作成でも User を作成して記録保存する
- User 未作成の雑談でも User を作成するが、Get profile は呼ばない

## 次に見ると理解しやすいファイル

- `spec/models/record_message_handler_spec.rb`
  - `:unrecognized` と `:parse_failed` の境界を model 単位で確認できます。

- `spec/models/line_messages_spec.rb`
  - 返信文が必要な情報を含むことを確認できます。

- `app/models/record_message_parser.rb`
  - 今回の直接変更対象ではありませんが、`parse_result.errors` の `reason` や `line_number` の前提を理解するために見る価値があります。

- `plan.md`
  - 9.5 の実施結果に、判断理由・TDD の流れ・見送り事項が詳しく残っています。

## 後回ししても良い箇所

- `LineMessages.input_guide`
  - 返信文で再利用していますが、今回の主目的は案内文そのものの改善ではありません。

- `LineMessages.recorded`
  - 正常保存時のエコーバックです。今回の変更では呼び出し分岐に含まれるだけで、文言の中心ではありません。

- `RecordMessageHandler.save`
  - 保存処理自体は既存の流れを維持しています。今回見るべき中心は、保存前の `Outcome` 分岐と `RecordInvalid` の扱いです。

- `handle_follow` / `handle_unfollow`
  - User 自己修復との比較対象にはなりますが、今回の変更の主対象ではありません。

## 今は無視して良い箇所

- 未知種目の候補提案
  - `:unknown_exercises` は今回も返信なしです。候補提案や postback は 10 章の作業範囲です。

- `postback` イベント
  - 10 章で実装予定です。今回のエラー応答では扱いません。

- Web ダッシュボード、グラフ、通常の workout 画面
  - 今回の変更は LINE Webhook のテキスト受信と返信に閉じています。

- request spec の Webhook helper 共通化
  - `post_event` / `text_event` / 署名計算は複数 spec に重複していますが、既存ファイルも含めた整理になるため今回は見送りです。

## レビュー時の確認順

1. `spec/requests/line_message_error_replies_spec.rb` を読み、今回保証したい外部振る舞いを把握する
2. `app/controllers/line_webhooks_controller.rb` の `handle_message` と `reply_text_for` を読む
3. `app/models/record_message_handler.rb` の `call` と `record_like?` を読む
4. `app/models/line_messages.rb` の `parse_failed` / `unrecognized` / `invalid` を読む
5. 必要に応じて `spec/models/record_message_handler_spec.rb` と `spec/models/line_messages_spec.rb` で境界条件を確認する

## Verification

`plan.md` 上の実施記録では、以下を確認済みです。

- RSpec 全件: 340 examples, 0 failures
- RuboCop: 指摘なし
- Brakeman: 警告 0

この資料のレビュー時（2026-09-30）に上記 3 点を再実行し、同じ結果（340 examples, 0 failures / RuboCop 指摘なし / Brakeman 警告 0）であることを確認済みです。
