# Stage 1 実装計画（plan.md）

- 根拠仕様書: `~/plans/SPEC-workout-tracker-20260723.md`（版 2.0 確定。以下「仕様書」）
- 対象: 仕様書の Stage 1（F-01〜F-07）のみ。Stage 2・Stage 3 の作業は含めない
- 進め方: ステップは依存関係順。完了したステップは `- [x]` に更新し、常に「どこまで終わり、次はどれか」を本ファイルで判断する
- 表記: 各ステップは「実施内容 → 完了条件」。必要に応じて対象（ファイル・テーブル・画面・ルート・テスト種別）を付記
- 分割方針: 各サブシステム内は「DB 制約 → ドメイン処理 → API 処理 → UI」の順に並べ、テストは各ステップの完了条件に内蔵する（テストを最後に集約しない）。全体を水平レイヤで貫かないのは、確認・決定ステップ（10.1/10.2 等）より前に DB を確定させないため、および各ステップを独立に検証可能へ保つため
- 「確認・決定」と付くステップは仕様書 10 章の未確定事項を解消する作業。決定結果は仕様書 10 章にも反映する

---

## 1. 環境構築

- [x] 1.1 Rails プロジェクト生成
  - 実施内容: Ruby 3.3.10（`.ruby-version`）で `rails new`（`--database=postgresql --skip-test`、Rails 8.1 系・importmap・Hotwire 既定）を本ディレクトリに実行する
  - 完了条件: `bin/rails -v` が成功し、生成物がコミット可能な状態で揃っている
- [x] 1.2 開発用 PostgreSQL の用意と DB 接続
  - 実施内容: `compose.yaml` に postgres:17 コンテナを定義して起動し、`config/database.yml` を接続設定（host/username/password）に合わせ、`bin/rails db:prepare` を実行する
  - 完了条件: development / test の DB が作成され、`bin/rails db:prepare` がエラーなく完了する
- [x] 1.3 RSpec ＋ FactoryBot の導入
  - 実施内容: Gemfile に `rspec-rails` `factory_bot_rails` を追加し、`rails g rspec:install` と FactoryBot の設定を行う
  - 完了条件: `bundle exec rspec` が 0 examples で正常終了する
- [x] 1.4 起動確認
  - 実施内容: `bin/rails server` を起動し、ヘルスチェック `/up` を確認する（ポート 3000 が他プロセス使用中の場合は別ポート）
  - 完了条件: `/up` が 200 を返す

## 2. 認証（F-01）

- [x] 2.1 Devise の導入
  - 実施内容: Gemfile に `devise` を追加し、`rails g devise:install` を実行、初期設定（default_url_options 等）を行う
  - 完了条件: Devise のインストールがエラーなく完了し、アプリが起動する
- [x] 2.2a users テーブルの作成（DB）
  - 実施内容: `rails g devise User` をベースに `name`（NOT NULL）カラムを追加したマイグレーションを作成・実行する。使用モジュールは仕様書 4.1.1（database_authenticatable / registerable / recoverable / rememberable / validatable）。LINE 系カラムは 8.1 で追加するため含めない
  - 対象: `users` テーブル
  - 完了条件: マイグレーションが成功し、schema に email 一意 index と name NOT NULL が反映されている
- [x] 2.2b User モデルの実装（ドメイン）
  - 実施内容: name のバリデーションと factory を実装する
  - 対象: `app/models/user.rb` / テスト種別: model spec
  - 完了条件: model spec（name 必須・email 一意）が通る
- [x] 2.3 会員登録・ログイン画面の動作確認
  - 実施内容: Devise 標準画面（`/users/sign_up` `/users/sign_in`）で登録・ログイン・ログアウトを確認し、request spec を作成する
  - 対象画面: 仕様書 4.4 画面 1 / テスト種別: request spec
  - 完了条件: ブラウザで登録〜ログインが成立し、request spec が通る
  - 決定（2026-07-31・ユーザー承認）: ログイン後の着地先として **最小 `home#index`（`root "home#index"`／`authenticate_user!`）を暫定設置**。本ダッシュボード（グラフ・サマリ）は **6.3 で置き換える**。合わせて sign_up に `name` 欄追加＋ApplicationController で `:sign_up` の `name` を permit、layout に flash を追加（2.1 保留分）
- [x] 2.4 開発用メール送信の設定
  - 実施内容: パスワードリセットメールを開発環境で確認できるよう letter_opener 等を設定する（本番メールは仕様書 10 章 #8 のとおり対象外）
  - 完了条件: 開発環境でリセットメールの内容を確認できる
  - 実施結果（2026-08-04）: `letter_opener` を development グループに追加し、`development.rb` に `delivery_method = :letter_opener` を設定。あわせて `config.mailer_sender` が Devise 生成時のプレースホルダのままだったため `no-reply@workout-tracker.example`（RFC 2606 の予約 TLD）へ変更。本番の差出人はホスティング確定時に決定（仕様書 10 章 #1 / #8）。開発環境で実際に送信し、`tmp/letter_opener/.../rich.html` に差出人・再設定リンクが出力されることを確認。request spec（`spec/requests/password_reset_spec.rb`）4件を追加

## 3. 種目マスタ（F-06 データ層）

- [x] 3.1 【確認・決定】プリセット種目リストの確定（仕様書 10 章 #5）
  - 実施内容: プリセット種目（20 件程度）の名称・カテゴリ（胸/背中/脚/肩/腕/体幹）・自重フラグの一覧を確定し、仕様書 10 章を更新する
  - 完了条件: seed 投入可能な一覧表が確定している
  - 決定（2026-08-07・ユーザー承認）: **22 件・6 カテゴリで確定**。一覧は仕様書 4.3.2（新設）、10 章 #5 は完了に更新。仕様書は版 2.1
    - 名称は正式名称・日本語に統一（略称は 4.3.1 の候補提案で拾う）
    - **時間ベース種目（プランク等）は除外**。入力フォーマット 4.2.2 が回数のみで秒数を表現できないため。10 章 #13 として新規に未確定化
    - `bodyweight` は「重量入力の**省略**を許すか」であり入力の可否ではない旨を仕様書 4.5 に補記。加重の有無が日によって変わる種目（ブルガリアンスクワット・腕立て伏せ・懸垂・ディップス）は true
- [x] 3.2 exercises テーブルの作成
  - 実施内容: 仕様書 4.5 の定義でマイグレーション作成（user_id NULL 可 FK、name、normalized_name、category、bodyweight、unique index `[user_id, normalized_name]`。user_id NULL 行の一意性担保方式＝`NULLS NOT DISTINCT` か部分 index かをここで決定）
  - 対象: `exercises` テーブル
  - 完了条件: マイグレーション成功。NULL user_id 同士の重複が DB で拒否されることをテストで確認
  - 決定（2026-08-07・ユーザー承認）: **`NULLS NOT DISTINCT` を採用**（部分 index 2 本方式は不採用）。仕様書 4.5 の記述をそのまま 1 本の index で表現でき可読性が高いため。PostgreSQL 15 以降が要件（実環境は 17.10、Rails 8.1.3.1 が `nulls_not_distinct:` と schema.rb ダンプに対応）。将来 PG 15 未満へ移行する場合は index の張り替えのみで部分 index 方式へ切り替え可能（データ移行不要）
  - 実施結果（2026-08-07）: `db/migrate/20260807023429_create_exercises.rb` を作成。`Exercise` モデルは 3.4 の作業のため、DB 制約は生 SQL で直接検証する `spec/db/exercises_table_spec.rb`（9 examples）を追加。`t.references :user` は `index: false`（複合 index が先頭列でカバーするため単独 index は作らない）
  - 自動レビューの指摘に対応（2026-08-07）: `bodyweight` の既定値テストが、ヘルパーのキーワード引数既定値により常に列を明示していたため **DB の default を検証できていなかった**。省略時は列自体を INSERT から外す構造に修正。`default: true` に変えるとテストが失敗することを実際に確認済み（修正前は変えても GREEN のままだった）
- [x] 3.3 種目名正規化ロジックの実装
  - 実施内容: 仕様書 4.3.1(1)（NFKC・前後空白除去（全角含む）・ひらがな→カタカナ・英字小文字化）を単独のクラス/モジュールとして実装する
  - 完了条件: `ベンチプレス　`・`ベンチぷれす` → `ベンチプレス` を含む unit spec が通る
  - 実施結果（2026-08-07）: `app/models/exercise_name_normalizer.rb`（module + `module_function` の `.call`）と `spec/models/exercise_name_normalizer_spec.rb`（20 examples）を追加。完了条件の 2 例は「仕様書 4.3.1(1) の例」で検証済み
    - 配置は `app/models` 配下。`plan.md` 3.3 が「単独のクラス/モジュール」を求め、`CLAUDE.md` の構造方針が「迷ったらまず model に置く」「Service Object の採否は未確定」であるため、`app/services` は作らなかった
    - ひらがな→カタカナの範囲は `ぁ-ゖ` → `ァ-ヶ`。`ん`（U+3093）までにすると `ゔ`（U+3094）が変換されないため
    - **仕様に記載のない入力の扱い**: `nil` と空白のみの入力は例外にせず空文字を返す。名前の presence 検証は Exercise モデルの責務（3.4）のため
    - **内部の空白は保持する**。仕様が定めるのは「前後空白の除去」のみであるため（`ベンチ プレス` はそのまま）
    - **ゼロ幅文字の除去を追加し、仕様書 4.3.1(1) にも反映（版 2.2）**。`strip` が全角空白を落とせないという指摘を受けて全空白文字を実測した結果、U+200B〜U+200D / U+2060 / U+FEFF が NFKC でも `strip` でも残ることが判明した。混入しても目視できず「見た目が同じなのに一致しない種目」を生むため、正規化段階で落とす
    - **適用順序に依存する**: 全角空白は NFKC が U+0020 に畳むため `strip` で足りる（NFKC を先に通さないと残る）。ゼロ幅文字は先頭にあると `strip` がそこで止まるため `strip` より先に除去する。この依存関係は仕様書とコードのコメント双方に明記した
- [x] 3.4 Exercise モデルの実装
  - 実施内容: バリデーション、保存時の normalized_name 自動設定、プリセット/独自のスコープを実装する
  - 対象: `app/models/exercise.rb` / テスト種別: model spec
  - 完了条件: model spec（正規化の自動設定・一意性）が通る
  - 変更（2026-08-12・ユーザー承認）: **「使用中の記録がある種目は削除不可」（仕様書 4.3）を 4.3 へ移動**。判定対象の `workout_sets` が 4.2 で作成されるため、本項目の時点では実装もテストもできない。削除制限は Exercise と WorkoutSet の関連に属する振る舞いであり、両モデルが揃う 4.3 で実装するのが責務として自然
  - 実施結果（2026-08-12）: `app/models/exercise.rb`・`spec/models/exercise_spec.rb`（13 examples）・`spec/factories/exercises.rb` を追加
    - スコープは `preset` / `owned_by(user)` / `available_for(user)` の3つ。`available_for` は「プリセット＋自分の種目」を返し、4.3.1 の照合フロー（ユーザー独自種目 → 共通プリセットの順）で使う想定
    - **一意性エラーは `:name` に付ける**。照合は `normalized_name` で行うが、利用者が入力するのは `name` であり、内部用の列にエラーを付けると画面に出ない。`validates :normalized_name, uniqueness:` では `:normalized_name` に付くため、独自バリデーションで `:name` に付け替えた
    - モデル検証と DB 制約の二層が効いていることを実 DB で確認（`invalid` かつ `validate: false` では `RecordNotUnique`）
- [x] 3.5 プリセット種目の seed 投入
  - 実施内容: 3.1 の一覧を `db/seeds.rb`（または seed 用ファイル）で投入する
  - 完了条件: `bin/rails db:seed` が冪等に実行でき（再実行で重複しない）、件数が一覧と一致する
  - 決定（2026-08-12・ユーザー承認）: **冪等性は「追加のみ」（`find_or_create_by!`）で担保する**。upsert 案は、同一視のキーが `normalized_name` であるため肝心の名称変更に効かず（キーが変わり新規行になる）、実効的な利点が category / bodyweight の修正に限られる一方、将来プリセット編集機能を入れた際に「ユーザーの変更を seed が黙って戻す」罠になるため不採用。一覧の修正が必要になった場合はマイグレーション等で明示的に行う
  - 実施結果（2026-08-12）: `db/seeds.rb` に仕様書 4.3.2 の 22 件を直接記述（seed は現状プリセットのみのためファイル分割しない）。`Exercise.preset.find_or_create_by!(name: ...)` で投入し、`normalized_name` はモデルの before_validation に任せる
    - `spec/db/seeds_spec.rb`（3 examples）: 22 件が仕様の一覧と一致・再実行で件数が変わらない・既存のユーザー独自種目（プリセットと同名を含む）に影響しない
    - 開発 DB でも `bin/rails db:seed` を 2 回実行し、22 件・6 カテゴリで重複なしを確認

## 4. 記録モデル（F-05 データ層）

- [x] 4.1 workouts テーブルの作成
  - 実施内容: 仕様書 4.5 の定義でマイグレーション作成（user_id FK NOT NULL、performed_on、note、unique index `[user_id, performed_on]`）
  - 対象: `workouts` テーブル
  - 完了条件: マイグレーション成功。同一ユーザー同一日の 2 件目が DB で拒否されることをテストで確認
  - 実施結果（2026-08-13）: `db/migrate/20260813025641_create_workouts.rb` を作成。Workout モデルは 4.3 の作業のため、3.2 と同方針で DB 制約を生 SQL で直接検証する `spec/db/workouts_table_spec.rb`（8 examples）を追加
    - 一意制約（同一ユーザー同一日の拒否・別日/別ユーザーの許可）、user_id / performed_on の NOT NULL、FK 違反、note の NULL 可を検証
    - `t.references :user` は `index: false`（複合 index が先頭列でカバーするため単独 index は作らない。3.2 と同判断）
- [x] 4.2 workout_sets テーブルの作成
  - 実施内容: 仕様書 4.5 の定義でマイグレーション作成（weight_kg decimal(5,1) NULL 可・>= 0、reps > 0、set_number > 0、unique index `[workout_id, exercise_id, set_number]`、index `[exercise_id]`）
  - 対象: `workout_sets` テーブル
  - 完了条件: マイグレーション成功。同一 workout×種目×set_number の重複が DB で拒否されることをテストで確認
  - 実施結果（2026-08-13）: `db/migrate/20260813041102_create_workout_sets.rb` を作成。数値の下限（weight_kg >= 0 / reps > 0 / set_number > 0）は DB の CHECK 制約として実装（モデル側のバリデーションは 4.3 で重ねる二層構成）。`spec/db/workout_sets_table_spec.rb`（15 examples）で一意制約・NOT NULL・FK・CHECK・weight_kg の NULL 可と境界値 0 を検証
    - `workout_id` の単独 index は複合 index が先頭列でカバーするため作らない（3.2/4.1 と同判断）。`exercise_id` の単独 index はグラフ集計の結合キーとして仕様どおり作成
    - 複合 unique index は既定の生成名が 63 バイト制限で切り詰められハッシュ付きになるため、`index_workout_sets_on_workout_and_exercise_and_set_number` を明示
    - テスト構造の学び: PostgreSQL は制約違反でトランザクションが中断されるため、DB spec は「1 example につき違反 1 回」で書く（複数違反を 1 example に入れると 2 回目以降が InFailedSqlTransaction になる）
- [x] 4.3 Workout / WorkoutSet モデルの実装
  - 実施内容: 関連・バリデーション（数値制約、自重種目の weight NULL 許容）・factory を実装する。あわせて**「使用中の記録がある種目は削除不可」（仕様書 4.3）を Exercise 側に実装する**（3.4 から移動。2026-08-12・ユーザー承認）
  - 対象: `app/models/workout.rb` `app/models/workout_set.rb` / テスト種別: model spec
  - 完了条件: model spec が通る
  - 作業分解（tdd-dev 実行管理用）:
    - [x] Workout モデル（関連・performed_on の検証・factory）
    - [x] WorkoutSet モデル（関連・数値制約・自重の weight NULL 許容・factory）
    - [x] Exercise の削除制限（使用中の記録がある種目は削除不可）
  - 実施結果（2026-08-14）: `app/models/workout.rb`（7 examples）・`app/models/workout_set.rb`（19 examples）・factory 2 件を追加、`Exercise` に削除制限を追加（+2 examples）。DB 制約とモデル検証の二層構成
    - Workout: `performed_on` の presence ＋ user 内一意。`has_many :workout_sets, dependent: :destroy`（記録は物理削除・仕様書 4.3）。User に `has_many :workouts, dependent: :destroy` を追加
    - WorkoutSet: reps / set_number は整数・> 0、set_number は workout×種目内で一意。weight_kg は >= 0 かつ < 1000 で `allow_nil`、**NULL の可否は種目の bodyweight で決まるため独自検証**（`bodyweight: false` なら必須。true でも入力可）
  - レビュー指摘に対応（2026-08-14・`@claude` メンションレビュー）: 上限 < 1000 を「decimal(5,1) に整合」と説明していたが**誤り**（decimal(5,1) の格納上限は 9999.9。整数部は precision - scale = 4 桁）。上限は「実用上の決め値」と訂正し、モデル単層だった上限を **DB CHECK 制約（`workout_sets_weight_kg_upper_bound`）を追加して二層に統一**。仕様書 4.5 にも上限を追記（版 2.3）
    - Exercise: `has_many :workout_sets, dependent: :restrict_with_error`。使用中は `destroy` が false を返しエラーが付く（実装前は DB FK の InvalidForeignKey 例外が生で出ることを RED で確認）
    - 一意性エラーは属性（`:performed_on` / `:set_number`）に付く標準動作のまま。normalized_name（3.4）のような内部列ではなく利用者が入力する属性のため付け替え不要
- [x] 4.4 セット採番と競合対策の実装
  - 実施内容: 「同一 workout×種目の最大 set_number の次から採番」（仕様書 4.5。例: 1,2,3 の後の追記は 4,5）を実装する。並行入力対策（workout 行ロック `SELECT FOR UPDATE` か一意制約違反リトライか）をここで決定して実装する
  - 完了条件: 追記採番の spec、および並行（または制約違反経路）の spec が通る
  - 決定（2026-08-14・ユーザー承認）: **workout 行ロック（`with_lock` = `SELECT FOR UPDATE`）を採用**。制約違反リトライは、PostgreSQL では制約違反でトランザクションが中断されるため savepoint か全体やり直しが必要になり複雑（4.2 のテストで確認済みの挙動）。行ロックは実装が一本道で読みやすく、LINE の複数行一括保存（仕様書 4.2.3。部分保存しない）とも相性がよい。本アプリの競合は同一ユーザーの LINE と Web 程度でロックのコストは無視できる
  - 実施結果（2026-08-14）: `Workout#append_set(exercise:, **attributes)` を実装。ロック → 種目内の最大 set_number ＋ 1 → create の順。バリデーションエラー時は未保存のレコード（エラー付き）を返す
    - `spec/models/workout_spec.rb` に採番の spec 6 examples（初回 1 / 1,2,3 の後は 4,5 / 種目・workout ごとに独立 / 歯抜け 1,3 の次は 4（「最大の次」の仕様を明文化）/ エラー時未保存）
    - `spec/models/workout_append_set_concurrency_spec.rb`（1 example）: **実コミット＋2 スレッドで並行実行**し、set_number が [1, 2] になることを検証（トランザクショナルテストでは別接続からデータが見えないため、このファイルのみ `use_transactional_tests = false`）
    - **テストの検証能力を mutation で確認**: `with_lock` を外すと並行 spec が失敗（RecordNotUnique）することを実際に確認してから戻した
- [ ] 4.5 セット削除時の繰り上げ処理の実装
  - 実施内容: 中間セット削除時に後続の set_number を同一トランザクションで繰り上げ、歯抜けを作らない（仕様書 4.5。小さい番号から順に更新）
  - 完了条件: 「1,2,3 から 2 を削除 → 1,2 に詰まる」spec が通る

## 5. Web 記録管理（F-05 / F-06 画面）

- [ ] 5.1 認証必須とユーザー分離の共通基盤
  - 実施内容: 全画面 `authenticate_user!` 必須（Webhook を除く）、リソースは常に `current_user` 起点で取得する方針をコントローラ共通で実装する（仕様書 2.3 / 8 章）
  - テスト種別: request spec（未ログイン→リダイレクト、他ユーザーの workout 参照→404）
  - 完了条件: 上記 request spec が通る
- [ ] 5.2 記録一覧画面
  - 実施内容: 日付降順の一覧（日付・種目数・総セット数）と月フィルタを実装する
  - 対象: ルート `/workouts`（仕様書 4.4 画面 3） / テスト種別: request spec
  - 完了条件: 画面が仕様の表示項目を満たし、spec が通る
- [ ] 5.3 記録詳細・編集画面
  - 実施内容: セット単位の表示・追加・修正・削除を実装する（削除時は 4.5 の繰り上げが作動）
  - 対象: ルート `/workouts/:id`（仕様書 4.4 画面 4） / テスト種別: request spec
  - 完了条件: 追加・修正・削除（繰り上げ含む）が画面から行え、spec が通る
- [ ] 5.4 種目管理画面
  - 実施内容: 独自種目の追加・名称変更・削除（使用中は削除不可）、プリセット一覧表示を実装する
  - 対象: ルート `/exercises`（仕様書 4.4 画面 5） / テスト種別: request spec
  - 完了条件: 仕様の操作が行え、使用中種目の削除が拒否されることを spec で確認

## 6. ダッシュボード・グラフ（F-07）

- [ ] 6.1 グラフ用集計の実装
  - 実施内容: 種目別推移（日付ごとの最大重量・推定 1RM = Epley 式 `weight × (1 + reps/30)`）と月間頻度（週/月ごとの実施日数）の集計を実装する（仕様書 4.4）
  - テスト種別: unit spec（集計値の検証）
  - 完了条件: 既知データに対する集計結果の spec が通る
- [ ] 6.2 グラフデータ JSON エンドポイントの実装
  - 実施内容: 6.1 の集計を返す JSON エンドポイントを実装する（種目・期間 1/3/6 ヶ月の指定、current_user スコープ）
  - テスト種別: request spec
  - 完了条件: 指定した種目・期間の JSON が返り、spec が通る
- [ ] 6.3 ダッシュボード画面の実装
  - 実施内容: Chart.js（importmap 経由）で種目別推移（折れ線 2 系列: 最大重量・推定 1RM、種目セレクト・期間切替）と月間頻度（棒）を描画し、当週サマリ（実施日数・総セット数）を表示する
  - 対象: ルート `/`（仕様書 4.4 画面 2）
  - 完了条件: ブラウザでグラフ 2 種とサマリが仕様どおり表示される（手動確認）。サマリ値は request spec で確認

## 7. LINE Webhook 基盤（F-03 前段）

- [ ] 7.1 【確認・決定】LINE 公式ドキュメントの制約値確認（仕様書 10 章 #3 #12）
  - 実施内容: replyToken の有効期限・再利用可否、Webhook 再送（redelivery）の有効化方法と再送回数/期間上限、webhookEventId の仕様、Reply API のレート制限を公式ドキュメントで確認し、仕様書 10 章を更新する
  - 完了条件: 確認結果が仕様書に反映され、7 章以降の実装判断に使える状態
- [ ] 7.2 LINE Developers チャネルの作成と資格情報の設定
  - 実施内容: Messaging API チャネルを作成（ユーザー操作を含む）し、channel secret / channel access token を Rails credentials（または環境変数）に設定する。リポジトリにコミットしないことを確認する
  - 完了条件: アプリから資格情報を参照でき、秘密情報が Git 管理外にある
- [ ] 7.3 LINE Bot SDK の導入
  - 実施内容: LINE 公式の Ruby SDK gem（line-bot-api）を Gemfile に追加し、クライアント初期化をまとめる
  - 完了条件: コンソールから SDK クライアントを初期化できる
- [ ] 7.4 Webhook エンドポイントと署名検証の実装
  - 実施内容: Webhook 用ルートとコントローラを作成し、`X-Line-Signature`（HMAC-SHA256）検証を実装する。検証失敗は 400、CSRF 保護は当該エンドポイントのみ除外（仕様書 4.2.4 / 8 章）
  - 対象: ルート例 `/webhooks/line` / テスト種別: request spec（正しい署名→200、不正署名→400）
  - 完了条件: 上記 spec が通る
- [ ] 7.5a processed_line_events テーブルの作成（DB）
  - 実施内容: 仕様書 4.5 の定義でマイグレーション作成（webhook_event_id **unique index**、received_at NOT NULL）
  - 対象: `processed_line_events` テーブル
  - 完了条件: マイグレーション成功。同一 webhook_event_id の 2 件目が DB で拒否されることをテストで確認
- [ ] 7.5b 冪等性（webhookEventId 重複排除）の実装（API 処理）
  - 実施内容: 「イベント ID 登録と業務処理を同一 DB トランザクションで行い、登録済みならスキップして 200」を実装する（仕様書 4.2.4）
  - テスト種別: request spec（同一イベント 2 回送信→処理は 1 回）
  - 完了条件: 重複イベントで業務処理が 1 回しか走らないことを spec で確認
- [ ] 7.6 エラー分類応答の実装
  - 実施内容: 仕様書 4.2.4 の分類（署名不正=400 / 業務エラー=200＋案内返信 / 一時障害（未コミット例外）=500）をコントローラのエラーハンドリングとして実装する
  - テスト種別: request spec（DB 例外を発生させて 500、パース失敗相当で 200）
  - 完了条件: 3 分類それぞれの spec が通る
- [ ] 7.7 Webhook 再送の有効化
  - 実施内容: LINE Developers コンソールで Webhook 再送（redelivery）を有効化する（7.1 の確認結果に従う。ユーザー操作を含む）
  - 完了条件: 再送設定が有効になっている

## 8. LINE アカウント連携（F-02）

- [ ] 8.1 users への LINE 関連カラム追加
  - 実施内容: `line_user_id`（unique・NOT NULL 行のみの部分 index）、`line_link_code`（unique）、`line_link_code_expires_at`、`line_blocked`（default false）を追加する（仕様書 4.5）
  - 対象: `users` テーブル
  - 完了条件: マイグレーション成功、一意制約のテストが通る
- [ ] 8.2a 連携コード発行・解除ロジックの実装（ドメイン）
  - 実施内容: 6 桁英数字コードの生成（一意・有効期限 10 分）と連携解除（line_user_id の NULL 化）をドメイン処理として実装する（仕様書 4.1.2）
  - テスト種別: model/unit spec（コード形式・期限・再発行時の置き換え）
  - 完了条件: unit spec が通る
- [ ] 8.2b LINE 連携設定画面の実装（UI）
  - 実施内容: 連携コード発行操作・連携状態表示・連携解除操作の画面を実装する
  - 対象: ルート `/settings/line`（仕様書 4.4 画面 6） / テスト種別: request spec
  - 完了条件: コード発行・表示・解除が画面から行え、spec が通る
- [ ] 8.3 Webhook での連携コード照合と総当たり対策
  - 実施内容: 連携コード形式のメッセージを照合し `line_user_id` を保存、完了/失敗（期限切れ・不一致）を返信する。同一 LINE ユーザーの照合失敗 5 回で一定時間ロックする（仕様書 4.1.2。ロック時間・保持方法はここで決定）
  - テスト種別: request spec（成功・期限切れ・不一致・ロック）
  - 完了条件: 4 ケースの spec が通る
- [ ] 8.4 follow / unfollow イベント処理
  - 実施内容: follow は未連携（挨拶＋連携手順）と連携済み再追加（`line_blocked` を false に戻し復帰挨拶）で分岐、unfollow は `line_blocked` を true にする（仕様書 4.2.1。記録は削除しない）
  - テスト種別: request spec（未連携 follow / 再追加 follow / unfollow）
  - 完了条件: 3 ケースの spec が通る（フラグの遷移を含む）

## 9. 記録入力の実装（F-03 / F-04）

- [ ] 9.1 【確認・決定】定型フォーマット表記ゆれテストケース表の確定（仕様書 10 章 #4）
  - 実施内容: 受理する/しない入力例の一覧（半角/全角スペース、kg・回・セットの表記、自重、複数行、境界値）を確定し、仕様書 10 章を更新する
  - 完了条件: 9.2 のテストに使えるケース表が確定している
- [ ] 9.2 定型フォーマットパーサーの実装
  - 実施内容: `<種目名> <重量>kg <回数>回 [<セット数>セット]`（セット省略=1、自重は重量省略可、複数行対応）を独立クラスとして実装する（仕様書 4.2.2）
  - テスト種別: unit spec（9.1 のケース表を網羅）
  - 完了条件: ケース表全件の spec が通る
- [ ] 9.3 種目照合（完全一致）の統合
  - 実施内容: パース結果の種目名を正規化し、ユーザー独自→プリセットの順で完全一致照合する（仕様書 4.3.1(2) 手順 1。候補提案は 10 章のステップで実装）
  - テスト種別: unit spec
  - 完了条件: 表記ゆれ（`ベンチぷれす` 等）が既存種目に解決される spec が通る
- [ ] 9.4 記録保存フローと成功応答の実装
  - 実施内容: 「冪等 ID 登録 → workout の find_or_create（競合はリトライ/4.2.4 準拠）→ セット採番・保存」を単一トランザクションで実装し、コミット後に保存内容のエコーバック（種目・重量・回数・セット数・当日合計）を Reply する（仕様書 2.3 / 4.2.3）
  - テスト種別: request spec（LINE API はモック）
  - 完了条件: 記録メッセージ→保存→エコーバックの spec が通る（複数行・自重・同日追記の採番継続を含む）
- [ ] 9.5 エラー応答の実装
  - 実施内容: パース失敗（失敗行とフォーマット例を返信、全行不保存）、未連携ユーザー（連携手順案内）、その他テキスト（ヘルプ案内）を実装する（仕様書 4.2.1 / 4.2.3）
  - テスト種別: request spec
  - 完了条件: 3 ケースの spec が通り、パース失敗時に DB へ一切保存されないことを確認
- [ ] 9.6 Reply API 呼び出し条件の実装
  - 実施内容: Reply は DB コミット後に呼び出し、短いタイムアウト（7.1 の確認結果に基づき決定）を設定、失敗時はリトライ・ロールバックせずログ記録に留める（仕様書 2.3 / 4.2.4）
  - テスト種別: unit/request spec（Reply 失敗でも記録が保存済みであること）
  - 完了条件: Reply 失敗時に保存が残り、エラーがログに出る spec が通る

## 10. 種目候補提案（F-03 続き・仕様書 4.3.1）

- [ ] 10.1 【確認・決定】pg_trgm の採否と閾値方針（仕様書 10 章 #9）
  - 実施内容: 前方一致・部分一致で不足するケースを検討し、pg_trgm 採用可否を決定する（採用時は extension 有効化と trigram index を 10.4 に含める）。仕様書 10 章を更新する
  - 完了条件: 採否と（採用時の）閾値の初期値が決定している
- [ ] 10.2 【確認・決定】Quick Reply / postback の上限確認（仕様書 10 章 #10）
  - 実施内容: Quick Reply のボタン数上限と postback data の長さ上限を公式ドキュメントで確認し、候補 4 件＋操作 2 件（新規登録・キャンセル）の設計が収まることを検証する。仕様書 10 章を更新する
  - 完了条件: 上限値が仕様書に反映され、ボタン構成が確定している
- [ ] 10.3 pending_workout_entries テーブルの作成
  - 実施内容: 仕様書 4.5 の定義で作成（user_id FK、source_text、parsed_lines jsonb、expires_at、**unique index `[user_id]`**）
  - 対象: `pending_workout_entries` テーブル
  - 完了条件: マイグレーション成功、同一ユーザー 2 件目の INSERT が拒否されることをテストで確認
- [ ] 10.4 候補検索の実装
  - 実施内容: 正規化名の前方一致・部分一致（＋10.1 で採用した場合は類似度検索）で候補を関連度順に最大 4 件返す検索を実装する（仕様書 4.3.1(2)）
  - テスト種別: unit spec（`ベンチ` → `ベンチプレス` 等）
  - 完了条件: 候補の抽出・順序・上限の spec が通る
- [ ] 10.5 保留エントリの作成と候補提示応答の実装
  - 実施内容: 未知種目を含む入力は全行を保留（既存保留は物理削除→新規作成を同一トランザクションで。UPDATE 不可）し、Quick Reply（候補最大 4 件＋新規種目として登録＋キャンセル）を返信する。postback データに保留 id を含める。unique 制約違反はリトライまたは 500（仕様書 4.3.1(3)）
  - テスト種別: request spec（保留の置き換え・並行時の一意性を含む）
  - 完了条件: 保留作成と Quick Reply 応答、後勝ちの置き換えの spec が通る
- [ ] 10.6 postback 処理の実装
  - 実施内容: 候補選択（該当行の種目を確定）、新規種目として登録（独自種目を作成して確定）、キャンセル（保留全体を破棄）を実装する。保留 id 不一致・不存在（stale postback）・期限切れは再入力案内を返す（仕様書 4.3.1(3)）
  - テスト種別: request spec（選択・新規登録・キャンセル・stale・期限切れ）
  - 完了条件: 5 ケースの spec が通る
- [ ] 10.7 全件確定時の一括保存の実装
  - 実施内容: 未知種目が複数ある場合は 1 件ずつ順に候補確認し、全件確定した時点で 9.4 の保存フローに合流して一括保存、保留行を削除する（部分保存しない）
  - テスト種別: request spec（未知 2 種目の順次確定→一括保存）
  - 完了条件: 順次確認〜一括保存の spec が通り、途中キャンセルで何も保存されないことを確認

## 11. コマンドとリッチメニュー（仕様書 4.2.1 / 4.2.5）

- [ ] 11.1 `ヘルプ` コマンドの実装
  - 実施内容: 記録フォーマットとコマンド一覧を返信する
  - テスト種別: request spec
  - 完了条件: spec が通る
- [ ] 11.2 `今日` コマンドの実装
  - 実施内容: 当日の記録サマリを返信する（記録なしの場合の文言を含む）
  - テスト種別: request spec
  - 完了条件: 記録あり/なし両方の spec が通る
- [ ] 11.3 `履歴` コマンドの実装
  - 実施内容: 直近 7 日の記録サマリとダッシュボード URL を返信する
  - テスト種別: request spec
  - 完了条件: spec が通る
- [ ] 11.4 リッチメニューの作成と適用
  - 実施内容: 4 ボタン構成（記録する=フォーマット例表示 / 今日の記録 / グラフを見る=ダッシュボード URL / ヘルプ）のリッチメニューを作成する rake タスク等を実装し、チャネルに適用する
  - 完了条件: 実機の LINE でリッチメニューが表示され、各ボタンが仕様どおり動作する

## 12. Stage 1 統合確認

- [ ] 12.1 実機 E2E 確認
  - 実施内容: ngrok / Cloudflare Tunnel で Webhook を公開し、実機 LINE で一連の流れを確認する: 友だち追加 → 連携コード連携 → 定型入力で記録 → エコーバック → 表記ゆれ入力の解決 → 未知種目の候補提案〜確定 → `今日`/`履歴` → Web ダッシュボードでグラフ・記録編集 → ブロック/再追加のフラグ遷移
  - 完了条件: 上記の全操作が実機で仕様どおり動作する
- [ ] 12.2 テスト・静的解析の全体実行
  - 実施内容: `bundle exec rspec`（全件）、`bundle exec rubocop`、`bin/brakeman` を実行し、失敗・重大指摘を解消する
  - 完了条件: すべて成功（許容する指摘があれば理由を記録）
- [ ] 12.3 仕様書との照合
  - 実施内容: 仕様書 4 章（4.1〜4.5）と 8 章の項目を 1 つずつ照合する: 機能 F-01〜F-07、画面 6 つ、テーブル 6 つ（users / exercises / workouts / workout_sets / pending_workout_entries / processed_line_events）と各 unique 制約、Webhook 応答分類（400/200/500）、冪等性、Reply 呼び出し条件、総当たりロック、line_blocked 遷移
  - 完了条件: 全項目が実装済み、または差異が理由付きで記録されている
- [ ] 12.4 未完了項目・未確定事項の棚卸し
  - 実施内容: 本ファイルの未チェック項目と、仕様書 10 章の未確定事項（Stage 1 対象: #3 #4 #5 #9 #10 #12 の解消確認。対象外: #1 ホスティング・#2 AI・#6 スケジューラ・#7 プロンプト・#8 本番メール・#11 トレーニング設定）を棚卸しし、残項目と対応方針を記録する
  - 完了条件: 残項目リストが本ファイル末尾に記録され、Stage 1 完了の判断材料が揃っている
