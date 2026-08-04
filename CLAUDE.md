# CLAUDE.md

このリポジトリで作業する際の規約を定める。Claude Code の全セッション（ローカル作業・GitHub Actions 上の自動レビュー）に適用される。

レビュー固有の指示（出力言語・コメント投稿先など）はここに書かない。それらは `.github/workflows/claude-review.yml` 側で指定する（→ `docs/pr-review-automation.md` 7章）。

---

## プロジェクト概要

筋トレの記録を管理する Web アプリケーション。Web 画面からの記録に加え、LINE からのメッセージによる記録入力を予定している。

現在は Stage 1（Web での認証・記録管理・ダッシュボード、および LINE 連携）を実装中。進捗と作業単位は `plan.md` で管理する。

**根拠となる詳細仕様書はリポジトリ外にある**（`~/plans/SPEC-workout-tracker-20260723.md`、版 2.0 確定。以下「仕様書」）。GitHub Actions 上のセッションからは参照できないため、仕様に関わる判断が必要な場合は推測せず、その旨を明示する。本ファイルに書かれた規約は、仕様書を参照できない環境でも守れるよう自己完結させる。

---

## 技術スタック

| 領域 | 採用 |
|---|---|
| 言語・フレームワーク | Ruby 3.3.10 / Rails 8.1 |
| データベース | PostgreSQL 17（開発環境は `compose.yaml` の Docker コンテナ） |
| 認証 | Devise |
| フロントエンド | Propshaft / importmap-rails / Turbo / Stimulus（Hotwire 既定構成） |
| グラフ描画 | Chart.js（importmap 経由。仕様書 2.1） |
| 非同期ジョブ | **Stage 1 では未導入。** Stage 2 で Sidekiq ＋ Redis を ActiveJob アダプタとして導入する（仕様書 2.1 / 5章） |
| テスト | RSpec / FactoryBot |
| 静的解析 | RuboCop（rubocop-rails-omakase）/ Brakeman / bundler-audit |
| デプロイ | Kamal（ホスティング先は未確定。仕様書 10章 #1） |

Gemfile の `solid_queue` / `solid_cache` / `solid_cable` は `rails new` の既定生成物であり、**いずれも設定・使用されていない**（`config/queue.yml` と `config/cache.yml` は存在せず、`config/cable.yml` の production は redis アダプタ、`app/channels` も無い）。**Solid Queue は不採用**（Sidekiq を採用する）。キャッシュと ActionCable の方針は未定。

新しい gem やライブラリの追加は、既存の選択で解決できないことを確認してから提案する。追加が必要な場合は理由とともに提案し、承認を得てから導入する。

---

## 開発フロー

- **TDD で実装する。** RED（失敗するテストを書く）→ GREEN（通す）→ REFACTOR の順を守る
- **環境構築の例外**: 依存パッケージの追加、設定ファイル（`config/environments/*` 等）、CI・Docker などの基盤構築で、**テスト環境に検証対象の振る舞いが存在しない作業に限り**、RED/GREEN を省略してよい。省略した場合は PR にその旨と理由を記載する。同じ項目にモデル・エンドポイント等の振る舞いの実装が含まれる場合、その部分には通常どおり TDD を適用する
- 作業単位は `plan.md` の1項目。1項目 ＝ 1トピックブランチ ＝ 1 PR を原則とする
- ブランチ運用・コミットメッセージ・マージ方式は `docs/branching-rules.md` に従う
- **コミット・push は依頼された場合のみ行う。** 自動的にコミットしない
- `main` への直接コミットは禁止

---

## コーディング規約

### スタイル

- RuboCop は rubocop-rails-omakase の設定に従う。**独自のスタイルルールを追加しない**
- 既存コードの命名・構造・パターンを踏襲する。周辺コードを読んでからスタイルを合わせる

### 構造

- Rails の標準構造（model / controller / concern / job / mailer）で書く
- ロジックの置き場所に迷った場合は、まず model に置く。model が肥大化した時点で `app/models/concerns` への切り出しを検討する

### 変更の粒度

- リファクタリング時は、明示的な指示がない限り挙動を変えない
- 依頼された範囲外のリファクタリングを行わない
- 不要なファイルの追加・移動・リネームを行わない

---

## セキュリティ

### ユーザーデータの分離（最重要）

- **リソースの取得は常に `current_user` を起点とする。** `Workout.find(params[:id])` のようにモデルから直接引かず、`current_user.workouts.find(params[:id])` の形で書く
- 全画面で `authenticate_user!` を必須とする。除外してよいのは LINE Webhook エンドポイントのみ
- CSRF 保護を除外してよいのは LINE Webhook エンドポイントのみ。他の箇所で `skip_forgery_protection` を使わない

### 秘密情報

- **このリポジトリは Public である。** 認証情報・API キー・トークン・LINE のチャネルシークレットをコードやコミットに含めない。一度 push すると公開履歴に残り、削除しても取り消せない
- 秘密情報は Rails の credentials または環境変数で扱う
- ログに個人情報（メールアドレス・ユーザー ID・リクエストボディ）を出力しない

---

## テスト

- **新しく追加した振る舞いには、必ず対応する spec を追加する。** spec のない実装は未完成とみなす（「開発フロー」の環境構築の例外に該当する作業を除く）
- テストの種類は、モデルの振る舞いは model spec、画面とエンドポイントは request spec を基本とする
- テストデータは FactoryBot の factory を使う。spec 内でモデルを直接 `create` する記述を積み重ねない
- バグ修正では、修正前に失敗する spec を先に書く
- 実行していないテストを「成功した」と扱わない

---

## データベース

- マイグレーションは後方互換を保つ。既存カラムの削除・リネームは、参照が残っていないことを確認してから行う
- 既存データを破壊する可能性のある変更は、実行前に必ず提案し承認を得る
- 外部キー制約と NOT NULL 制約は、仕様上許容される限り付ける
- 検索・絞り込みに使うカラムにはインデックスを検討する

---

## 検討中（未確定）

以下は方針が固まっていない。ここに書かれた内容は確定した規約として扱わない。

- **Service Object / Form Object の採否。** 現在は導入しておらず、`app/services` も存在しない。Stage 1 の範囲では標準構造で足りる見込みだが、LINE Webhook の処理（パース・種目照合・保存を跨ぐ）で判断が必要になる可能性がある
- **View の構造化方針**（partial の粒度、ViewComponent の採否）

---

## 参照ドキュメント

| ファイル | 内容 |
|---|---|
| `plan.md` | Stage 1 の実装計画と進捗。各ステップに仕様書の該当節が付記されている |
| `docs/branching-rules.md` | ブランチ・PR・コミット・マージの運用ルール |
| `docs/pr-review-automation.md` | PR 自動レビューの仕様 |
