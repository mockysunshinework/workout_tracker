# PR 自動レビュー仕様書（workout_tracker）

GitHub Actions 上で Claude Code を実行し、Pull Request に対するコードレビューを自動化する仕様を定める。

- 対象リポジトリ: `workout_tracker`（Public / ソロ開発）
- 版: 1.0（2026-08-03 策定）
- 関連ドキュメント: [`docs/branching-rules.md`](./branching-rules.md)
- ステータス: **仕様策定済み・未実装**（本ドキュメント以外のファイルは未変更）

---

## 1. 背景と目的

### 1.1 解決したい課題

現状、`main` への直接 push は Ruleset で禁止されており、変更は必ず PR 経由で入る。しかし Ruleset の Required approvals は `0` であり、CI（`scan_ruby` / `scan_js` / `lint` / `test`）が green になれば誰のレビューも経ずにマージできる。

PR テンプレートには「差分を自分で一読した」というチェック項目があるが、これは自己申告であり、実効的なレビュー工程は存在しない。結果として **PR #8〜#11 はいずれもレビューを経ずに `main` にマージされている**。

### 1.2 目的

- PR に対して機械的にレビューが入る状態をつくり、「レビュー工程が存在しない」状態を解消する
- 単独開発でも、実務と同じ「レビューコメントを読んで対応する」ループを回せるようにする
- 追加の金銭コストを発生させずに導入する

### 1.3 目的としないこと

- 人間のレビューの完全な代替。AI レビューはあくまで一次チェックであり、最終判断は開発者が行う
- マージのブロック。本仕様のレビューは PR をブロックしない（→ [12章](#12-将来の拡張)）

---

## 2. 前提条件

導入前に確認済みの事実を記載する。

| 項目 | 確認結果 | 確認方法 |
|---|---|---|
| リポジトリ公開設定 | Public | `gh api repos/... --jq .visibility` |
| GitHub Actions の課金 | Public リポジトリのため標準ランナーは無料 | GitHub 公式の課金ポリシー |
| main ブランチ保護 | Ruleset `protect main` が有効（PR 必須 / force push 禁止 / linear history / Required approvals 0） | `gh api repos/.../rulesets` |
| 既存 CI | `.github/workflows/ci.yml` に `scan_ruby` / `scan_js` / `lint` / `test` の4ジョブ | ファイル確認 |
| Claude 契約プラン | Claude Max 5x（個人アカウント / 組織ロール admin） | ローカル設定 |
| Claude Code バージョン | 2.1.220 | `claude --version` |
| `claude setup-token` | 利用可（help に "requires Claude subscription" と明記） | `claude setup-token --help` |
| `claude_code_oauth_token` 入力 | `anthropics/claude-code-action` の `action.yml` に定義あり | action.yml L70-72 |
| Pro/Max での利用可否 | 公式に「Pro and Max users can generate this by running `claude setup-token` locally」と明記 | 同リポジトリ `docs/setup.md` L10, L223 |
| action の保守状況 | 最新リリース v1.0.183（2026-07-25） | `gh release list` |
| リポジトリ内 `CLAUDE.md` | **存在しない** | ファイル確認 |

### 2.1 採用しない選択肢とその理由

Anthropic 公式のマネージド Code Review（GitHub App のみで動作し、`@claude review` でレビューが走るサービス）は **Team / Enterprise サブスクリプション限定**であり、個人 Max プランでは利用できない。また 1 レビューあたり $15〜25 の従量課金が発生する。

本仕様は、これとは別系統の **自前の GitHub Actions 上で `anthropics/claude-code-action` を動かす方式**を採る。両者は名称が似ているため混同しやすいが、別物である。

| | マネージド Code Review | 本仕様（claude-code-action） |
|---|---|---|
| 実行場所 | Anthropic のインフラ | 自リポジトリの GitHub Actions |
| 必要なもの | GitHub App のみ | GitHub App ＋ ワークフロー ＋ Secret |
| 個人 Max での利用 | 不可 | **可** |
| 課金 | 1 レビュー $15〜25 の別課金 | サブスク枠を消費（追加課金なし） |

---

## 3. スコープ

### 3.1 対象

- `.github/workflows/claude-review.yml` の新規作成
- GitHub App（Claude）のリポジトリへのインストール
- リポジトリ Secret `CLAUDE_CODE_OAUTH_TOKEN` の登録
- `docs/branching-rules.md` への運用手順の追記
- `.github/pull_request_template.md` へのチェック項目追加

### 3.2 対象外

- 既存 `.github/workflows/ci.yml` の変更
- Ruleset の変更（必須ステータスチェックへの追加を含む）
- リポジトリ `CLAUDE.md` / `REVIEW.md` の新規作成（→ [12章](#12-将来の拡張)）
- アプリケーションコード・テストコードの変更
- レビュー指摘の自動修正・自動コミット

---

## 4. 全体構成

```
[開発者] PR を作成/更新
              │
              ├──> pull_request イベント ──> auto-review ジョブ
              │                                  │
              │                                  ├─ 総評を PR コメントに投稿
              │                                  └─ 具体箇所をインラインコメントに投稿
              │
              └──> PR に "@claude ..." とコメント
                            │
                            └──> issue_comment イベント ──> mention ジョブ
                                                                │
                                                                └─ 質問への回答 / 再レビュー
```

2つのジョブは同一ワークフローファイル内に置き、`if:` 条件でイベント種別により振り分ける。

---

## 5. 認証設計

### 5.1 方式

`CLAUDE_CODE_OAUTH_TOKEN`（OAuth トークン方式）を採用する。

**採用理由**: Max のサブスクリプション枠を消費するため、API 従量課金が発生しない。Public リポジトリのため GitHub Actions の実行時間も無料であり、導入・運用の金銭コストが実質ゼロになる。

**採用しなかった選択肢**: `ANTHROPIC_API_KEY`（API 従量課金）。全機能が確実に動作する利点があるが、PR ごとに課金が発生する。

### 5.2 トークン発行手順

```bash
# ローカルの Claude Code で実行
claude setup-token
```

出力されたトークンを、GitHub の以下の場所に登録する。

```
Settings → Secrets and variables → Actions → New repository secret
  Name:  CLAUDE_CODE_OAUTH_TOKEN
  Value: (発行されたトークン)
```

### 5.3 取り扱い規約

- トークンをワークフローファイル・コミット・PR・Issue に**絶対に直書きしない**。本リポジトリは Public のため、一度 push すると公開履歴に残り取り消せない
- 参照は必ず `${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}` の形で行う
- 漏洩が疑われる場合は、GitHub 側の Secret を削除したうえで `claude setup-token` を再実行し、新しいトークンを登録する

### 5.4 既知の制約

- トークンの有効期限は、CLI のヘルプにも公式ドキュメントにも記載が見つかっていない（**未確認**）。認証エラーで失敗し始めた場合は失効を疑い、再発行する
- インラインコメント分類機能（`classify_inline_comments`）は `anthropic_api_key` を要すると公式に明記されている。OAuth トークン使用時の挙動については記載がなく、**未確認**。インラインコメントの投稿自体は `mcp__github_inline_comment__create_inline_comment` ツールで行うため動作するはずだが、実運用で確認する

---

## 6. ワークフロー仕様

### 6.1 ファイル配置

```
.github/workflows/claude-review.yml
```

既存の `ci.yml` とは分離する。理由は、CI（テスト・静的解析）とレビューは目的も失敗時の意味も異なり、片方の変更が他方に影響しない構成が望ましいため。

### 6.2 トリガー仕様

| イベント | types | 発火するジョブ | 用途 |
|---|---|---|---|
| `pull_request` | `opened` / `synchronize` / `reopened` / `ready_for_review` | `auto-review` | PR 作成・更新時の自動レビュー |
| `issue_comment` | `created` | `mention` | PR コメントでの `@claude` 呼び出し |
| `pull_request_review_comment` | `created` | `mention` | インラインコメントでの `@claude` 呼び出し |
| `pull_request_review` | `submitted` | `mention` | レビュー本文での `@claude` 呼び出し |

`synchronize`（PR ブランチへの push）を含めるため、1 PR で複数回レビューが走る。これは [6.4](#64-実行制御) の同時実行制御で緩和する。消費を抑えたい場合は `synchronize` を `on:` から外し、再レビューは `@claude review` で明示的に依頼する運用に切り替えられる。

### 6.3 ジョブ仕様

#### `auto-review`

| 項目 | 値 |
|---|---|
| 実行条件 | `pull_request` イベント かつ 下記スキップ条件に該当しないこと |
| タイムアウト | 20 分 |
| 権限 | `contents: read` / `pull-requests: write` / `issues: read` / `id-token: write` / `actions: read` |
| 許可ツール | インラインコメント作成、`gh pr comment` / `gh pr diff` / `gh pr view` / `gh pr checks` |
| 最大ターン数 | 20 |

コード変更権限（`contents: write`）は与えない。レビューはコメント投稿のみを行い、コードを書き換えないという方針を権限レベルで担保する。

#### `mention`

| 項目 | 値 |
|---|---|
| 実行条件 | コメント本文に `@claude` を含むこと |
| タイムアウト | 30 分 |
| 権限 | `contents: write` / `pull-requests: write` / `issues: write` / `id-token: write` / `actions: read` |
| 最大ターン数 | 20 |

修正依頼にも応えられるよう `contents: write` を与える。ただし action の既定動作として **Claude は PR を自動作成せず**、ブランチにコミットしたうえで PR 作成ページへのリンクを提示するのみである（公式 `docs/security.md`）。最終的な PR 作成は開発者が行う。

### 6.4 実行制御

同時実行制御はジョブ単位で設定する。

- `auto-review`: グループキーを PR 番号とし、`cancel-in-progress: true`。連続 push 時に古いレビューを打ち切り、無駄な消費を防ぐ
- `mention`: グループキーをコメント ID とし、`cancel-in-progress: false`。複数の質問が互いを打ち切らないようにする

### 6.5 スキップ条件

`auto-review` は以下のいずれかに該当する場合、実行しない。

| 条件 | 理由 |
|---|---|
| Draft PR（`ready_for_review` を除く） | 未完成の差分をレビューしても価値が低い |
| `github.actor == 'dependabot[bot]'` | **Dependabot が起動した `pull_request` イベントには Actions Secret が渡らない**ため、必ず認証エラーで失敗する。依存更新 PR のレビューは `docs/branching-rules.md` 9章の手順（ローカルでのテスト・bundler-audit）で担保する |
| fork からの PR | 同じく Secret が渡らないため失敗する。ソロ開発のため通常発生しないが、Public リポジトリのため防御的に除外する |

### 6.6 ワークフロー定義

```yaml
name: Claude Review

on:
  pull_request:
    types: [opened, synchronize, reopened, ready_for_review]
  issue_comment:
    types: [created]
  pull_request_review_comment:
    types: [created]
  pull_request_review:
    types: [submitted]

jobs:
  auto-review:
    # Draft / dependabot / fork PR はスキップ（6.5 参照）
    if: >-
      github.event_name == 'pull_request' &&
      github.event.pull_request.draft == false &&
      github.actor != 'dependabot[bot]' &&
      github.event.pull_request.head.repo.full_name == github.repository
    runs-on: ubuntu-latest
    timeout-minutes: 20
    concurrency:
      group: claude-auto-review-${{ github.event.pull_request.number }}
      cancel-in-progress: true
    permissions:
      contents: read
      pull-requests: write
      issues: read
      id-token: write
      actions: read

    steps:
      - name: Checkout code
        uses: actions/checkout@v6
        with:
          fetch-depth: 1

      - name: Review pull request
        uses: anthropics/claude-code-action@v1
        with:
          claude_code_oauth_token: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
          track_progress: true
          prompt: |
            REPO: ${{ github.repository }}
            PR NUMBER: ${{ github.event.pull_request.number }}

            この Pull Request をレビューしてください。PR ブランチは作業ディレクトリに
            チェックアウト済みです。

            ## 出力ルール

            - すべて日本語で書いてください。ただしファイル名・識別子・コード片は
              原文（英語）のまま引用してください。
            - 総評は `gh pr comment` で PR に1件だけ投稿してください。
            - 個別の指摘は mcp__github_inline_comment__create_inline_comment を
              使い、該当行にインラインコメントとして投稿してください
              （`confirmed: true` を指定）。
            - GitHub へのコメント投稿のみを行い、レビュー本文をメッセージとして
              返さないでください。
            - コードの編集・コミットは行わないでください。

            ## 重要度の表記

            各指摘の先頭に必ず次のいずれかを付けてください。

            - 🔴 要修正: マージ前に直すべきバグ・セキュリティ問題
            - 🟡 改善提案: 直したほうがよいが、マージをブロックしない
            - 🟣 既存の問題: この PR が原因ではないが、周辺に見つかった問題

            🟡 は最大5件までとし、それ以上は総評に件数だけ記載してください。
            指摘が1件もない場合は、総評に「指摘なし」と明記してください。

            ## レビュー観点（優先順）

            1. 正確性のバグ: ロジック誤り、境界値・nil の扱い、例外時の挙動、
               トランザクション境界、競合状態
            2. ユーザーデータの分離: リソース取得が常に `current_user` 起点に
               なっているか。他ユーザーのデータに到達しうる経路がないか
            3. 認証・認可: Devise の設定漏れ、`authenticate_user!` の適用漏れ、
               CSRF 保護を外している箇所の妥当性
            4. マイグレーション: 後方互換性、NOT NULL 制約とデフォルト値、
               既存データへの影響、インデックスの過不足
            5. Active Record: N+1 クエリ、不要な全件取得、スコープ漏れ
            6. テスト: 追加された振る舞いに対する RSpec が存在するか。
               テストが実装の写経になっていないか
            7. 秘密情報: 認証情報・APIキー・トークンが差分に混入していないか
               （本リポジトリは Public のため特に重要）

            ## 指摘しないこと

            - RuboCop（rails-omakase）が検出するスタイル・フォーマットの問題
            - Brakeman / bundler-audit / importmap audit が検出する問題
              （いずれも CI で自動チェック済みのため重複を避ける）
            - 個人の好みに属する命名・設計の言い換え提案

          claude_args: |
            --max-turns 20
            --allowedTools "mcp__github_inline_comment__create_inline_comment,Bash(gh pr comment:*),Bash(gh pr diff:*),Bash(gh pr view:*),Bash(gh pr checks:*)"

  mention:
    # コメント本文に @claude を含む場合のみ発火
    if: >-
      (github.event_name == 'issue_comment' &&
       github.event.issue.pull_request != null &&
       contains(github.event.comment.body, '@claude')) ||
      (github.event_name == 'pull_request_review_comment' &&
       contains(github.event.comment.body, '@claude')) ||
      (github.event_name == 'pull_request_review' &&
       contains(github.event.review.body, '@claude'))
    runs-on: ubuntu-latest
    timeout-minutes: 30
    concurrency:
      group: claude-mention-${{ github.event.comment.id || github.event.review.id }}
      cancel-in-progress: false
    permissions:
      contents: write
      pull-requests: write
      issues: write
      id-token: write
      actions: read

    steps:
      - name: Checkout code
        uses: actions/checkout@v6
        with:
          fetch-depth: 1

      - name: Run Claude Code
        uses: anthropics/claude-code-action@v1
        with:
          claude_code_oauth_token: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
          claude_args: |
            --max-turns 20
            --append-system-prompt "回答は日本語で行う。ファイル名・識別子・コード片は原文のまま引用する。コードを変更する場合も、変更理由を日本語で説明する。"
```

### 6.7 使い方

| やりたいこと | 操作 |
|---|---|
| 通常のレビュー | PR を作成する（自動で走る） |
| 修正後の再レビュー | PR ブランチに push する（自動で走る） |
| push せずに再レビュー | PR に `@claude この PR をもう一度レビューして` とコメント |
| 指摘内容の質問 | PR に `@claude この指摘の意図を詳しく説明して` とコメント |
| 指摘の修正を依頼 | PR に `@claude この指摘を修正して` とコメント（ブランチにコミットされる） |
| 観点を絞ったレビュー | PR に `@claude マイグレーションの後方互換性だけ見て` とコメント |

---

## 7. 既存運用への統合

以下は本仕様で定める変更内容であり、**本ドキュメント作成時点では未適用**。

### 7.1 `docs/branching-rules.md` の改訂

7.1 節の標準作業フローに、PR 作成後の待ち工程を追加する。

```diff
  # 6. CI が green になるのを待つ
+
+ # 6b. Claude の自動レビューコメントを読み、対応要否を判断する
+ #     🔴 要修正 は原則すべて対応してからマージする
+ #     🟡 改善提案 / 🟣 既存の問題 は判断のうえ、見送る場合は理由を PR に残す
  
  # 7. Squash merge（CI green 後）
```

7.2 節「PR の運用」に以下を追加する。

- Claude のレビューコメントを確認したうえでマージする。**AI の指摘は一次チェックであり、採否は必ず自分で判断する**。指摘が誤っている場合はその旨を PR に記録し、鵜呑みにしない
- 自動レビューが失敗した場合（認証エラー・タイムアウト等）は、`@claude review` で再実行するか、ローカルで `/code-review` を実行して代替する

9章「dependabot PR の扱い」に以下を追記する。

- dependabot の PR には Secret が渡らないため自動レビューは走らない。従来どおりローカルでのテストと `bundler-audit` / `bundle check` で確認する

11章に本ドキュメントへの参照を追加する。

### 7.2 `.github/pull_request_template.md` の改訂

```diff
  ## 確認したこと
  - [ ] `bundle exec rspec` が green
  - [ ] `bin/rubocop` が green
  - [ ] 差分を自分で一読した
+ - [ ] Claude のレビューコメントを確認し、🔴 要修正 に対応した（または対応不要と判断した理由を記載した）
```

---

## 8. セキュリティ設計

| 論点 | 評価 | 対応 |
|---|---|---|
| Public リポジトリで第三者が `@claude` を悪用し、サブスク枠を消費される | action 側で対策済み。公式 `docs/security.md` に「The action can only be triggered by users with write access to the repository」と明記されており、書き込み権限のないユーザーはトリガーできない | 追加対応なし。`allowed_non_write_users` は**設定しない** |
| Bot によるトリガー | 既定で GitHub App / Bot はトリガーできない | `allowed_bots` を**設定しない**（特に `'*'` は設定しない） |
| プロンプトインジェクション | PR 本文やコメントに隠し指示が埋め込まれるリスク。action は HTML コメント・不可視文字・画像 alt 等をサニタイズするが、完全ではないと公式に明記 | ソロ開発のため外部入力は実質的に自分の書いたものに限られる。将来外部から PR を受ける場合は `include_comments_by_actor` による許可リスト運用を検討する |
| Secret の露出 | ワークフローファイルは Public だが Secret 値は含まれない。fork PR / dependabot PR には Secret が渡らない | `${{ secrets.* }}` 参照のみとし、直書きを禁止（[5.3](#53-取り扱い規約)） |
| `pull_request_target` の使用 | fork PR で Secret にアクセスできてしまう危険なトリガー | **使用しない**。fork PR は [6.5](#65-スキップ条件) でスキップする |
| Claude による意図しないコード変更 | `auto-review` ジョブは `contents: read` のみで、そもそも書き込めない | 権限で担保。`mention` ジョブは `contents: write` を持つが、PR 作成は行わず開発者の操作を要する |

---

## 9. コストとレート制限

| 項目 | 見込み |
|---|---|
| GitHub Actions 実行時間 | **無料**（Public リポジトリの標準ランナー） |
| API 従量課金 | **なし**（OAuth トークンによるサブスク認証のため） |
| Claude Max 5x の利用枠 | 消費する |

### 9.1 利用枠に関する注意

同一アカウントのトークンを使うため、GitHub Actions でのレビューがローカルの Claude Code 利用枠と共有されると推測される。ただし合算方法の明記は公式ドキュメントに見つかっておらず、**未確認**である。

実装後に枠の消費が想定より大きい場合、次の順で調整する。

1. `on: pull_request` の `types` から `synchronize` を外し、再レビューは `@claude review` の明示依頼に切り替える
2. `--max-turns` を 20 から 10 程度に下げる
3. `paths-ignore` を追加し、`docs/**` や `plans/**` のみの変更ではレビューを走らせない

---

## 10. 導入手順

各手順の完了後に次へ進む。

- [ ] 10.1 ローカルで `claude setup-token` を実行し、OAuth トークンを発行する
- [ ] 10.2 GitHub の Settings → Secrets and variables → Actions に `CLAUDE_CODE_OAUTH_TOKEN` を登録する
- [ ] 10.3 Claude GitHub App（https://github.com/apps/claude ）を `workout_tracker` にインストールする。権限は Contents / Issues / Pull requests の Read & Write
- [ ] 10.4 トピックブランチ `ci/claude-pr-review` を作成する
- [ ] 10.5 `.github/workflows/claude-review.yml` を [6.6](#66-ワークフロー定義) の内容で作成する
- [ ] 10.6 `docs/branching-rules.md` を [7.1](#71-docsbranching-rulesmd-の改訂) のとおり改訂する
- [ ] 10.7 `.github/pull_request_template.md` を [7.2](#72-githubpull_request_templatemd-の改訂) のとおり改訂する
- [ ] 10.8 PR を作成し、[11章](#11-動作検証)の検証を行う
- [ ] 10.9 検証結果を PR に記録し、squash merge する

> 10.3 の GitHub App インストールは、ローカルの Claude Code で `/install-github-app` を実行して対話的に行うこともできる。ただしこのコマンドは既定で `ANTHROPIC_API_KEY` を前提とした手順を案内するため、Secret 名は本仕様の `CLAUDE_CODE_OAUTH_TOKEN` に読み替える。手動でのインストールでも同等である。

---

## 11. 動作検証

| # | 検証内容 | 手順 | 期待結果 |
|---|---|---|---|
| 11.1 | 自動レビューが起動する | 10.8 の PR を作成する | `Claude Review / auto-review` ジョブが実行される |
| 11.2 | 認証が通る | 同ジョブのログを確認する | 認証エラーが出ず完走する |
| 11.3 | 総評が投稿される | PR の Conversation タブを確認する | 日本語の総評コメントが1件投稿されている |
| 11.4 | インラインコメントが投稿される | PR の Files changed タブを確認する | 該当行にインラインコメントが付く（[5.4](#54-既知の制約) の未確認事項の検証を兼ねる） |
| 11.5 | 重要度表記が機能する | 投稿内容を確認する | 各指摘に 🔴 / 🟡 / 🟣 が付いている |
| 11.6 | 再レビューが走る | PR ブランチに追加コミットを push する | 新しい `auto-review` が起動し、古い実行がキャンセルされる |
| 11.7 | メンションが機能する | PR に `@claude この PR の要約を日本語で教えて` とコメントする | `mention` ジョブが起動し、日本語で応答が投稿される |
| 11.8 | Draft ではスキップされる | Draft PR を作成する | `auto-review` が起動しない |
| 11.9 | dependabot でスキップされる | 次回の dependabot PR で確認する | `auto-review` が起動しない（起動して失敗しない） |
| 11.10 | 既存 CI に影響がない | 同 PR の Checks を確認する | `scan_ruby` / `scan_js` / `lint` / `test` が従来どおり実行され green |

11.9 は dependabot の weekly 実行を待つ必要があるため、他項目と分けて後日確認する。

---

## 12. 将来の拡張

現時点では実施しないが、運用が安定したのち検討する。

### 12.1 リポジトリ `CLAUDE.md` の追加

`claude-code-action` はリポジトリ直下の `CLAUDE.md` をプロジェクト規約として読み込む。本リポジトリには現在存在しないため、レビューは汎用的な観点に留まる。`docs/branching-rules.md` の要点、仕様書の参照先、Rails 8 / Devise / RSpec / rails-omakase という技術選択を `CLAUDE.md` に集約すれば、レビュー精度と一貫性が上がる見込み。

### 12.2 マージゲート化

`auto-review` ジョブを Ruleset の必須ステータスチェックに追加すると、「レビューが走っていない PR はマージできない」状態を構造的に作れる。

ただしこれで担保できるのは「レビューが実行されたこと」までで、「🔴 要修正 が残っていないこと」をマージ条件にするには、レビュー結果を機械可読な形で出力し判定する追加実装が必要となる。実現方法は**未確認**。

導入を急がない理由は、レビュー待ちで作業が止まる場面が増え、単独開発のテンポを損なう可能性があるため。まず自動レビューを回し、指摘の質と所要時間を把握してから判断する。

### 12.3 ローカル `/code-review` との併用

Claude Code には `/code-review` コマンドがあり、push 前にローカルで差分をレビューできる。CI に出す前の一次チェックとして併用でき、`docs/branching-rules.md` 11.3 が定める「ローカル品質チェックと CI の二層」の考え方と整合する。本仕様の代替ではなく補完として位置づける。

---

## 13. リスクと対応

| リスク | 可能性 | 影響 | 対応 |
|---|---|---|---|
| OAuth トークンの失効により自動レビューが静かに止まる | 中 | 中 | 認証エラーはジョブ失敗として PR の Checks に現れる。失敗を見つけたら再発行する（[5.2](#52-トークン発行手順)） |
| インラインコメントが投稿されず総評のみになる | 中 | 低 | [5.4](#54-既知の制約) の未確認事項。11.4 で検証する。動作しない場合は総評コメントのみの運用でも目的は達成できる |
| AI の誤指摘に従って不要な変更を入れる | 中 | 中 | 「採否は必ず自分で判断する」を運用ルールに明記（[7.1](#71-docsbranching-rulesmd-の改訂)）。自動修正機能は使わない |
| レビュー時間が長く、マージのテンポが落ちる | 中 | 低 | タイムアウトを 20 分に設定。マージをブロックしないため、待たずにマージすることも可能 |
| サブスク利用枠を想定以上に消費する | 中 | 中 | [9.1](#91-利用枠に関する注意) の調整手順で段階的に絞る |
| Public リポジトリでの第三者トリガー | 低 | 中 | action 側で書き込み権限チェック済み（[8章](#8-セキュリティ設計)） |
| レビューの存在に安心して差分を自分で読まなくなる | 中 | 高 | PR テンプレートの「差分を自分で一読した」項目を維持する。AI レビューは追加の層であり、置き換えではない |

---

## 14. ロールバック方針

| 対象 | 手順 |
|---|---|
| ワークフロー | `.github/workflows/claude-review.yml` を削除して push する。以後レビューは走らない |
| ドキュメント | `docs/branching-rules.md` / `.github/pull_request_template.md` の変更を revert する |
| Secret | Settings → Secrets and variables → Actions から `CLAUDE_CODE_OAUTH_TOKEN` を削除する |
| GitHub App | Settings → GitHub Apps → Claude → Configure からリポジトリのアクセスを外す、またはアンインストールする |
| DB 変更 | **DB 変更なし** |

不可逆な変更は含まれない。ワークフローファイルの削除だけでレビューは即座に停止する。

---

## 15. 未確認事項

実装・運用の中で確認し、判明したら本ドキュメントを更新する。

| # | 内容 | 確認タイミング |
|---|---|---|
| 15.1 | `claude setup-token` で発行されるトークンの有効期限 | 運用中に認証エラーが出た時点 |
| 15.2 | OAuth トークン使用時のインラインコメント投稿の可否 | 11.4 |
| 15.3 | GitHub Actions での利用が Max の枠とどう合算されるか | 数 PR 運用したのち |
| 15.4 | 1 PR あたりの実行時間と枠の消費量 | 11.1〜11.7 の実測 |
| 15.5 | 「🔴 要修正 が残っていたらブロック」の実現方法 | 12.2 を検討する時点 |

---

## 16. 参照

- [Claude Code GitHub Actions（公式ドキュメント）](https://code.claude.com/docs/en/github-actions)
- [anthropics/claude-code-action](https://github.com/anthropics/claude-code-action)
  - `docs/setup.md` — 認証方式
  - `docs/security.md` — アクセス制御・プロンプトインジェクション
  - `docs/solutions.md` — 自動 PR レビューの構成例
- [Code Review（マネージドサービス / Team・Enterprise 限定）](https://code.claude.com/docs/en/code-review)
- [`docs/branching-rules.md`](./branching-rules.md) — ブランチ運用ルール

---

## 変更履歴

- 1.0（2026-08-03）: 初版策定。GitHub Actions ＋ `claude-code-action@v1` ＋ OAuth トークン認証による自動レビューと `@claude` メンションの併用構成。
