# Quick Reply / postback の上限と、ボタン構成の決定（plan.md 10.2）

LINE で未知の種目名が送られたとき、候補をボタンで提示する「Quick Reply」が LINE の上限に収まるかを確認し、ボタンの構成を決めるための資料。
plan.md 10.2「Quick Reply / postback の上限確認」の調査内容と、決定のための材料をまとめる（2026-10-06 調査）。

- ステータス: **決定済み（2026-10-06・ユーザー承認・仕様書 版 3.4）**。末尾の「決定」欄を参照。この調査から派生した種目名エイリアスの議論と決定は [`docs/exercise-alias-decision.md`](./exercise-alias-decision.md)
- 前提知識は不要。候補提案の全体像は [`docs/exercise-candidate-search.md`](./exercise-candidate-search.md)、LINE 入力の全体像は [`docs/line-record-flow.md`](./line-record-flow.md)

---

## 1. なにを決めるのか

LINE に `ベンチ60/5/3` と送って `ベンチ` が種目マスタに無いとき、仕様書 4.3.1(2) はこう返信する想定になっている。

```
「ベンチ」に一致する種目がありません。どれを記録しますか？
[ベンチプレス] [インクラインベンチプレス] [新規種目として登録] [キャンセル]
```

下段のボタンが LINE の **Quick Reply**。ユーザーがボタンを押すと、Bot には **postback イベント**が届き、アプリは「どの保留入力に対して、どの操作が選ばれたか」を読み取って保存を確定する。

ここで LINE 側の制約が 2 つ関わる。

1. ボタンは何個まで置けるか（候補 4 件＋新規登録＋キャンセル＝ 6 個が収まるか）
2. ボタンに埋め込める情報はどれだけか（保留 id・種目 id などが収まるか、ボタンの表示文字は何文字までか）

仕様書 10 章 #10 がこれを「要公式ドキュメント確認」として残していたので、公式リファレンスと OpenAPI 定義で確定させた。

---

## 2. Quick Reply の仕組み（最低限）

Quick Reply は、返信メッセージに `quickReply.items` として付けるボタンの配列。1 つのボタンは **label（表示文字）** と **action（押したときの動作）** を持つ。候補提案では action に **postback** を使う。

```json
{
  "type": "text",
  "text": "「ベンチ」に一致する種目がありません。どれを記録しますか？",
  "quickReply": {
    "items": [
      {
        "type": "action",
        "action": {
          "type": "postback",
          "label": "ベンチプレス",
          "data": "action=choose&pending_id=123&exercise_id=45",
          "displayText": "ベンチプレス"
        }
      }
    ]
  }
}
```

postback action の 3 つのフィールドの役割は次のとおり。

| フィールド | 役割 | ユーザーに見えるか |
|---|---|---|
| `label` | ボタンに表示される文字 | 見える |
| `data` | 押したときに Bot へ送られる文字列。アプリの識別子を入れる | 見えない |
| `displayText` | 押したときにトーク画面へ「ユーザーの発言」として表示される文字 | 見える（任意） |

ポイントは、**ボタンの見た目（label）とアプリへ渡す情報（data）が分かれている**こと。見た目は短く、情報は data に持たせればよい。

---

## 3. 公式ドキュメントで確認した上限

| 項目 | 上限 | 出典 |
|---|---|---|
| Quick Reply のボタン数 | 1 メッセージに **最大 13 個** | Messaging API リファレンス `items` object（OpenAPI の `maxItems: 13` と一致） |
| ボタンの `label` | **必須・最大 20 文字** | リファレンス「Specifications of the label」の Quick reply button 行 |
| postback の `data` | **必須・最大 300 文字** | リファレンス Postback action（OpenAPI `maxLength: 300`） |
| postback の `displayText` | **任意・最大 300 文字** | 同上 |
| postback の `text` | 非推奨。Quick Reply では使わない（`displayText` を使う） | 同上 |
| 文字数の数え方 | `label` / `displayText` は**書記素クラスタ単位**（日本語 1 文字 = 1） | 「Character counting in a text」 |
| 表示の仕組み | 複数メッセージを返した場合は**最後のメッセージの quickReply だけ**表示される。ユーザーがボタンを押すか、誰かが新しいメッセージを送ると消える | リファレンス Quick reply、「Use quick replies」 |

補足:
- 「書記素クラスタ単位」とは、人が 1 文字と認識する単位で数えるという意味。結合文字や絵文字が複数のコードポイントで構成されていても 1 文字と数える。日本語の種目名では「見た目の文字数 = カウント」と考えてよい
- Ruby では `String#grapheme_clusters` / `each_grapheme_cluster` がこの単位に対応する。`String#length`（コードポイント数）とは異なる場合がある

---

## 4. 設計が上限に収まるかの検証

| 観点 | 設計 | 判定 |
|---|---|---|
| ボタン数 | 候補 4 件＋新規登録＋キャンセル＝ **6 個** | 上限 13 に対して余裕あり。10.7 の「未知種目が複数ある場合」も 1 件ずつ順に確認するので 6 個のまま |
| `data` | 保留 id・操作・種目 id のみ（例 `action=choose&pending_id=123&exercise_id=45`）で **約 40 文字** | 上限 300 に対して余裕あり |
| `label` | 仕様書の例 `「ベンチ」を新規種目として登録` は 15 文字 | **入力名が 6 文字以上で上限 20 を超える**（例 `「ブルガリアンスクワット」を新規種目として登録` は 21 文字）。候補ボタンも、ユーザー独自種目の名前には長さ制限が無いため超過し得る → **要変更** |
| 消える仕組み | 保留中に別の記録を送ると Quick Reply が消える | 仕様書 4.3.1(3)「新しい入力が来たら既存の保留を破棄（後勝ち）」と整合。表示側と DB 側の状態が一致する |

### `data` にユーザー入力を含めない理由

`data` には「どの保留に対する操作か」を表す id だけを入れ、ユーザーが入力した種目名は入れない。

- 入力名を入れると長さ超過を気にする必要が出る（`data` は 300 文字で切り詰め不可。超えると送信自体が失敗する）
- 新規登録する名前は、保留エントリ（`pending_workout_entries.parsed_lines`）側に既に保持されている。postback を受けたら保留 id から引けばよく、`data` に重複して持つ必要がない
- stale postback（破棄済み保留のボタン）の無効化は id 再採番で担保する設計（4.3.1(3)）なので、`data` が id を含めば足りる

### `label` だけが問題になる理由

`label` は 20 文字と短く、かつ**ユーザーが決める文字列（種目名）を表示する唯一の場所**。プリセット種目で最長の `インクラインベンチプレス` は 12 文字で収まるが、独自種目の名前には長さ制限が無いので、どんな名前でも表示できる仕組みが必要になる。

---

## 5. ボタン構成の提案

| ボタン | `label`（表示・20 文字以内） | `displayText`（押したときの発言） | `data` |
|---|---|---|---|
| 候補（最大 4 件） | 種目名。20 文字超は **19 文字＋「…」に切り詰め**（書記素単位） | 種目名（切り詰めなし） | `action=choose&pending_id=<保留id>&exercise_id=<種目id>` |
| 新規登録 | **「新規種目として登録」（固定 9 文字）**。入力名は案内文側に `「ベンチ」に一致する種目がありません` として表示 | 「ベンチを新規種目として登録」 | `action=create&pending_id=<保留id>` |
| キャンセル | 「キャンセル」 | 「キャンセル」 | `action=cancel&pending_id=<保留id>` |

仕様書の例からの変更点は **新規登録ボタンの label に入力名を含めない**こと。入力名は本文（案内文）に表示されているので、ボタンに繰り返さなくても何を登録するかは分かる。

変更前後の見た目:

```
変更前（4.3.1(2) 手順 4 の例）
  「ブルガリアンスクワット」に一致する種目がありません。
  [「ブルガリアンスクワット」を新規種目として登録] [キャンセル]   ← 21 文字で送信失敗

変更後
  「ブルガリアンスクワット」に一致する種目がありません。
  [新規種目として登録] [キャンセル]
```

補足:
- `displayText` は任意だが、設定しないとボタンを押しても画面に何も残らず、ユーザーが何を選んだか後から分からない。候補名・操作名をそのまま入れる
- `displayText` も 300 文字が上限。種目名は 300 文字を超えないのが通常だが、`Exercise` の `name` に長さ制限が無い（`app/models/exercise.rb` は presence のみ）ため、10.5 の実装では `label` と同様に上限で切り詰めるか、`name` に妥当な長さ制限を設けるかを決める

---

### 派生: 別名確認のボタン（10.2b）

この調査の途中で「`ベンチ` と送ると毎回聞かれるのか」という問いから、候補選択後に「今後『ベンチ』はベンチプレスとして記録しますか？ [はい] [いいえ]」と確認して別名を学習する方式が決まった（経緯は [`docs/exercise-alias-decision.md`](./exercise-alias-decision.md)）。このボタンも同じ上限内に収まる。

| ボタン | `label` | `displayText` | `data` |
|---|---|---|---|
| はい | 「はい」 | 「今後「ベンチ」はベンチプレスとして記録」 | `action=alias_confirm&alias_id=<別名id>` |
| いいえ | 「いいえ」 | 「今回は登録しない」 | `action=alias_decline&alias_id=<別名id>` |

確認はエコーバック（記録完了の返信）と同じメッセージに付ける。Quick Reply は最後のメッセージにしか付かないため、独立メッセージにしない。

---

## 6. 仕様書への反映内容（版 3.4・反映済み）

1. 4.3.1(2) 手順 4 の例を `[「ベンチ」を新規種目として登録] [キャンセル]` → `[新規種目として登録] [キャンセル]` に改めた
2. 4.3.1(2) に上限値（ボタン 13 個 / label 20 文字 / data 300 文字 / displayText 300 文字・書記素単位）を追記した
3. 設計方針として「`data` にユーザー入力を含めない（id のみ）」「`label` は 20 文字で切り詰める（19 文字＋…）」を追記した
4. 10 章 #10 を完了にした

---

## 7. 実装（10.5 / 10.6）への申し送り

- `label` の切り詰めは `String#grapheme_clusters` で書記素単位に行う（`String#length` ではない）。spec で「20 文字ちょうど」「21 文字」「結合文字を含む名前」を確認する
- `data` の形式（`action=choose&pending_id=&exercise_id=`）は 10.6 の postback 処理側でパースする。`action` の取り得る値は候補提案の `choose` / `create` / `cancel` と、別名確認の `alias_confirm` / `alias_decline` の 5 つ
- 複数メッセージを返す場合（例: 案内文＋候補）、Quick Reply は**最後のメッセージ**に付ける
- `line-bot-api` 2.x でのクラス名（`Line::Bot::V2::MessagingApi::QuickReply` 等）は実装時に確認する

---

## 8. 決定

| 項目 | 決定 | 日付 |
|---|---|---|
| ボタン構成 | **5 章の案を採用**。候補（label は 20 文字で切り詰め）＋「新規種目として登録」（固定文言）＋「キャンセル」。`data` は id のみ | 2026-10-06 |
| 別名確認のボタン | **[はい] [いいえ] をエコーバックに付ける**（5 章「派生」）。詳細は `docs/exercise-alias-decision.md` | 2026-10-06 |
| 仕様書の反映 | **版 3.4 で反映済み**（6 章の 4 点＋ #17 の確定） | 2026-10-06 |

plan.md 10.2 に反映済み。10.5（保留作成と Quick Reply 応答）・10.6（postback 処理）で実装する。

---

## 出典

- [Messaging API reference](https://developers.line.biz/en/reference/messaging-api/)（Quick reply / items object / Postback action / Specifications of the label）
- [Use quick replies](https://developers.line.biz/en/docs/messaging-api/using-quick-reply/)
- [Character counting in a text](https://developers.line.biz/en/docs/messaging-api/text-character-count/)
- [line-openapi `messaging-api.yml`](https://github.com/line/line-openapi)（`maxItems: 13` / `maxLength: 300`）
