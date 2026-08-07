# PR 自動レビュー仕様書（workout_tracker）

GitHub Actions 上で Claude Code の公式 `code-review` プラグインを実行し、Pull Request に対するコードレビューを自動化する仕様を定める。

- 対象リポジトリ: `workout_tracker`（Public / ソロ開発）
- 版: 2.4（2026-08-07 改訂）
- 関連ドキュメント: [`docs/branching-rules.md`](./branching-rules.md) / リポジトリ直下の `CLAUDE.md`
- ステータス: **PoC 前提の暫定仕様**。ワークフロー・Secret・GitHub App は導入済み。`workflow_dispatch` 経由でレビューの完走を確認済みだが、**`pull_request` 経由での成功はまだ0件**（[12.5b](#125b-第1回検証の結果2026-08-04)）

> **本仕様は PoC（実証）を経て確定させる。** 未検証の前提が複数あり、特に [16.1](#16-未確認事項) の `--comment` 引数は、これが誤っていると**レビューが実行されても PR に何も投稿されない**。導入したら必ず [12章](#12-poc実証) を実施すること。

---

## 1. 背景と目的

### 1.1 解決したい課題

`main` への直接 push は Ruleset で禁止されており、変更は必ず PR 経由で入る。しかし Ruleset の Required approvals は `0` であり、CI（`scan_ruby` / `scan_js` / `lint` / `test`）が green になれば誰のレビューも経ずにマージできる。

PR テンプレートには「差分を自分で一読した」というチェック項目があるが、これは自己申告であり、実効的なレビュー工程は存在しない。結果として **PR #8〜#11 はいずれもレビューを経ずに `main` にマージされている**。

### 1.2 目的

- PR に対して機械的にレビューが入る状態をつくり、「レビュー工程が存在しない」状態を解消する
- 単独開発でも、実務と同じ「レビューコメントを読んで対応する」ループを回せるようにする
- 追加の金銭コストを発生させずに導入する

### 1.3 目的としないこと

- 人間のレビューの完全な代替。AI レビューは一次チェックであり、最終判断は開発者が行う
- マージのブロック。本仕様のレビューは PR をブロックしない（→ [17.2](#172-マージゲート化)）
- レビュー指摘の自動修正・自動コミット

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
| `claude_code_oauth_token` 入力 | `action.yml` に定義あり | claude-code-action の action.yml L70-72 |
| Pro/Max での利用可否 | 「Pro and Max users can generate this by running `claude setup-token` locally」と明記 | 同リポジトリ `docs/setup.md` L10, L223 |
| action の保守状況 | 最新リリース v1.0.183（2026-07-25） | `gh release list` |
| 公式 `code-review` プラグイン | `anthropics/claude-code` の marketplace に登録あり（`plugins/code-review`） | marketplace.json |
| リポジトリ直下の `CLAUDE.md` | 草案を作成済み（未コミット。→ [11.1](#111-phase-0-claudemd-の整備)） | ファイル確認 |
| **ワークフロー変更を含む PR ではレビューが走らない** | **確認済み（PR #13）。** action は「ワークフローファイルがデフォルトブランチ上の内容と一致すること」を実行条件としており、不一致なら処理をスキップして**ジョブは success で終了**する。PR でワークフローを書き換えて Secret を持ち出す攻撃への対策 | PR #13 の `auto-review` ジョブログ |
| 詳細仕様書 | **リポジトリ外**（`~/plans/SPEC-workout-tracker-20260723.md`）。プラグインは `CLAUDE.md` しか読まないため、リポジトリ内に置いてもレビュー内容は変わらない（→ [4.1](#41-プラグインの挙動確認済み)） | プラグインのコマンド定義を精読 |

### 2.1 採用しない選択肢とその理由

Anthropic 公式のマネージド Code Review（GitHub App のみで動作し `@claude review` でレビューが走るサービス）は **Team / Enterprise サブスクリプション限定**であり、個人 Max プランでは利用できない。また 1 レビューあたり $15〜25 の従量課金が発生する。

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

- **`CLAUDE.md` の新規作成**（リポジトリ直下）。レビュー品質の土台であり、最初に実施する（→ [11.1](#111-phase-0-claudemd-の整備)）
- `.github/workflows/claude-review.yml` の新規作成
- Claude GitHub App のリポジトリへのインストール
- リポジトリ Secret `CLAUDE_CODE_OAUTH_TOKEN` の登録
- `docs/branching-rules.md` への運用手順の追記
- `.github/pull_request_template.md` へのチェック項目追加
- [12章](#12-poc実証)の PoC 実施と、その結果に基づく本仕様の確定

### 3.2 対象外

- 既存 `.github/workflows/ci.yml` の変更
- Ruleset の変更（必須ステータスチェックへの追加を含む）
- `REVIEW.md` の作成。これは**マネージド Code Review 専用**の仕組みであり、claude-code-action もローカルの `/code-review` も読まない（→ [7章](#7-claudemd-と-workflow-の役割分担)）
- アプリケーションコード・テストコードの変更（[12.3](#123-検証用-pr既知欠陥の仕込み) の検証用 PR を除く）

---

## 4. 全体構成

```
[開発者] PR を作成 / Draft を Ready に変更
              │
              └──> pull_request イベント ──> auto-review ジョブ
                                                 │
                                                 └─ code-review プラグインを実行
                                                      ├─ skip 判定（haiku）
                                                      ├─ CLAUDE.md 収集（haiku）
                                                      ├─ 差分要約（sonnet）
                                                      ├─ 4エージェント並列レビュー
                                                      │    ├─ CLAUDE.md 準拠 ×2（sonnet）
                                                      │    └─ バグ検出 ×2（opus）
                                                      ├─ 指摘ごとの検証サブエージェント
                                                      ├─ 確信度 80 未満を除外
                                                      └─ 総評＋インラインコメントを投稿

[開発者] PR に "@claude ..." とコメント
              │
              └──> issue_comment 等 ──> mention ジョブ（Q&A・再レビュー依頼）
```

### 4.1 プラグインの挙動（確認済み）

`plugins/code-review/commands/code-review.md`（全109行）を精読して確認した事実。

| 項目 | 内容 |
|---|---|
| skip 条件 | closed / draft / **些末で明らかに正しい変更** / **既に Claude がコメント済みの PR** |
| CLAUDE.md の扱い | 4エージェント中**2つが CLAUDE.md 準拠チェック専任**。ファイルパスの階層を考慮して適用範囲を判定する |
| 検出基準 | ①コンパイル・パースが通らない ②入力に依らず確実に誤った結果を返す ③CLAUDE.md の規則違反で該当箇所を引用できる |
| 除外（false positive）リスト | 既存の問題 / 実は正しいコード / シニアが指摘しない些末事 / linter が拾う問題 / **一般的な品質懸念（テストカバレッジ不足・一般的なセキュリティ懸念を含む）— ただし CLAUDE.md に明記があれば対象** / lint ignore で明示的に抑止済みの箇所 |
| 確信度 | 指摘ごとに検証サブエージェントを立てて裏取りし、80 未満を除外 |
| 投稿 | 総評を `gh pr comment`、個別指摘を `mcp__github_inline_comment__create_inline_comment`（`confirmed: true`）。小さな修正には committable suggestion を付ける |
| 指摘ゼロ時 | `--comment` 指定時のみ「No issues found. Checked for bugs and CLAUDE.md compliance.」を投稿 |
| 許可ツール | コマンド定義の frontmatter で規定（`gh pr comment` / `gh pr diff` / `gh pr view` / `gh pr list` / `gh issue view` / `gh issue list` / `gh search` / インラインコメント MCP）。**`gh api` は含まれない** |

### 4.2 この挙動から導かれる設計上の帰結

1. **`CLAUDE.md` がなければレビュー戦力が半減する。** 4エージェント中2つが仕事をできなくなるため、`CLAUDE.md` の整備を導入手順の最初に置く（[11.1](#111-phase-0-claudemd-の整備)）
2. **テストの欠落は既定では指摘されない。** 除外リストに `lack of test coverage` が明記されているため、TDD を運用するなら `CLAUDE.md` に明示的に書く必要がある
3. **`synchronize` を使ってはならない。** 「既に Claude がコメント済みの PR はスキップ」するため、2回目以降の push でレビューが無言でスキップされる（[6.2](#62-トリガー仕様)）
4. **`track_progress` を有効にしてはならない。** この機能は実行前に PR へ進捗追跡コメントを投稿するが、それをプラグインの skip 判定が「Claude が既にコメント済み」と解釈し、**自分自身のコメントで自分をスキップさせる**恐れがある（[6.6](#66-ワークフロー定義) / 検証項目 [12.2](#122-検証項目) No.7）
5. **`--allowedTools` は両ジョブとも必須。** action は `prompt` を指定した agent モードで、**`claude_args` の `--allowedTools` だけを見て MCP サーバの起動可否を決める**（`src/modes/agent/index.ts` の `parseAllowedTools(userClaudeArgs)` → `src/mcp/install-mcp-server.ts`）。プラグイン側 frontmatter の `allowed-tools` は action からは見えない。したがって `mcp__github_inline_comment__` を挙げないと**インラインコメント用 MCP サーバが起動せず、レビューが完走しても投稿できない**。action のソースにも整合性が壊れやすい旨の警告コメントがある（issue #1357）。`gh api` は挙げない（[9章](#9-セキュリティ設計)）

   > **当初この項目には「`auto-review` では `--allowedTools` を渡さない。許可ツールはプラグイン側の frontmatter が規定するため」と記載していたが誤りだった。** 2026-08-07 の PR #19 で、レビューは17ターン・$1.05 で完走したにもかかわらず投稿されず（`permission_denials_count: 6`）、action のソースを読んで判明した。公式 `docs/solutions.md` の例が `--allowedTools` に MCP ツールを含めているのはこの条件を満たすためである。

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

- トークンの有効期限は、CLI のヘルプにも公式ドキュメントにも記載が見つかっていない（**未確認** → [16.2](#16-未確認事項)）
- インラインコメント分類機能（`classify_inline_comments`）は `anthropic_api_key` を要すると公式に明記されている。OAuth トークン使用時の挙動は記載がなく、**未確認**（→ [16.3](#16-未確認事項)）。インラインコメントの投稿自体はプラグインが MCP ツールで行うため動作するはずだが、PoC で確認する

---

## 6. ワークフロー仕様

### 6.1 ファイル配置

```
.github/workflows/claude-review.yml
```

既存の `ci.yml` とは分離する。CI（テスト・静的解析）とレビューは目的も失敗時の意味も異なり、片方の変更が他方に影響しない構成が望ましいため。

### 6.2 トリガー仕様

| イベント | types | 発火するジョブ | 用途 |
|---|---|---|---|
| `pull_request` | `opened` / `reopened` / `ready_for_review` | `auto-review` | PR 作成時の自動レビュー |
| `issue_comment` | `created` | `mention` | PR コメントでの `@claude` 呼び出し |
| `pull_request_review_comment` | `created` | `mention` | インラインコメントでの `@claude` 呼び出し |
| `pull_request_review` | `submitted` | `mention` | レビュー本文での `@claude` 呼び出し |

**`synchronize`（PR ブランチへの push）は含めない。** プラグインは「既に Claude がコメント済みの PR」をスキップするため、`synchronize` を含めても2回目以降は無言でスキップされ、「レビューが走ったのか止まったのか分からない」状態になる。ジョブは成功扱いで終わるため気づけない。

修正後の再レビューは `@claude` メンションで明示的に依頼する（[6.7](#67-使い方)）。

### 6.3 ジョブ仕様

#### `auto-review`

| 項目 | 値 | 根拠 |
|---|---|---|
| 実行条件 | `pull_request` イベント かつ [6.5](#65-スキップ条件) に該当しない |
| タイムアウト | 30 分 | 多エージェント構成のため単発プロンプトより長い |
| 権限 | `contents: read` / `pull-requests: write` / `issues: read` / `id-token: write` / `actions: read` | レビューがコードを書き換えないことを権限で担保 |
| `--max-turns` | 30 | オーケストレータがサブエージェント起動・裏取り・投稿を行うためターン数が嵩む。**上限であって予算ではなく、下げても平均消費は減らず長い PR が途中で打ち切られるだけ**であるため、低く設定しない |
| `track_progress` | **設定しない** | [4.2](#42-この挙動から導かれる設計上の帰結) 参照 |
| `--allowedTools` | **必須。** MCP ツール ＋ プラグインが使う `gh` 系 | 挙げないとインラインコメント用 MCP サーバが起動せず投稿できない（[4.2](#42-この挙動から導かれる設計上の帰結)） |

#### `mention`

| 項目 | 値 | 根拠 |
|---|---|---|
| 実行条件 | コメント本文に `@claude` を含む |
| タイムアウト | 30 分 |
| 権限 | `contents: read` / `pull-requests: write` / `issues: write` / `id-token: write` / `actions: read` | **`contents: write` を与えない**。理由は下記 |
| `--allowedTools` | **明示指定する**（読み取り系＋`gh pr` 系のみ） | `auto-review` と違いプラグインを通さないため、ツール制限が効かない。Claude App のトークンが広い権限を持つことへの実効的な対策（[9章](#9-セキュリティ設計)） |

`contents: write` を与えれば `@claude 修正して` でコミットまで行えるが、**意図的に与えない**。指摘を読んで自分で直す工程そのものが本仕様の目的（[1.2](#12-目的)）であり、権限を絞ることは制約ではなく設計判断である。コードの修正はローカルの Claude Code で行う。

将来この判断を見直す条件: レビュー指摘の修正が定型作業に収束し、自分で書く学習価値が失われたと判断できた場合。

### 6.4 実行制御

- `auto-review`: グループキーを PR 番号とし `cancel-in-progress: true`
- `mention`: グループキーをコメント ID とし `cancel-in-progress: false`（複数の質問が互いを打ち切らないようにする）

### 6.5 スキップ条件

`auto-review` は以下のいずれかに該当する場合、実行しない。

| 条件 | 理由 |
|---|---|
| Draft PR（`ready_for_review` を除く） | プラグイン側でもスキップされるが、無駄なジョブ起動を避けるため手前で止める |
| `github.actor == 'dependabot[bot]'` | **Dependabot が起動した `pull_request` イベントには Actions Secret が渡らない**ため、必ず認証エラーで失敗する。依存更新 PR のレビューは `docs/branching-rules.md` 9章の手順で担保する |
| fork からの PR | 同じく Secret が渡らないため失敗する。ソロ開発のため通常発生しないが、Public リポジトリのため防御的に除外する |

### 6.6 ワークフロー定義

```yaml
name: Claude Review

on:
  pull_request:
    # synchronize は含めない（6.2 参照）
    types: [opened, reopened, ready_for_review]
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
    timeout-minutes: 30
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
        uses: actions/checkout@v7
        with:
          fetch-depth: 1

      - name: Review pull request
        uses: anthropics/claude-code-action@v1
        with:
          claude_code_oauth_token: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
          plugin_marketplaces: "https://github.com/anthropics/claude-code.git"
          plugins: "code-review@claude-code-plugins"
          # --comment がないとプラグインは PR に何も投稿しない（16.1 / 12.2 No.1）
          prompt: "/code-review:code-review ${{ github.repository }}/pull/${{ github.event.pull_request.number }} --comment"
          # track_progress と --allowedTools は意図的に設定しない（4.2 参照）
          claude_args: |
            --max-turns 30
            --append-system-prompt "GitHub に投稿するレビューコメントは、総評・インラインコメントともにすべて日本語で記述する。ファイル名・識別子・コード片・CLAUDE.md からの引用は原文のまま扱う。"

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
      # contents: write は意図的に与えない（6.3 参照）
      contents: read
      pull-requests: write
      issues: write
      id-token: write
      actions: read

    steps:
      - name: Checkout code
        uses: actions/checkout@v7
        with:
          fetch-depth: 1

      - name: Run Claude Code
        uses: anthropics/claude-code-action@v1
        with:
          claude_code_oauth_token: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
          # auto-review と違いプラグインを通さないため、ツールをここで明示的に制限する（9章参照）
          claude_args: |
            --max-turns 20
            --allowedTools "Read,Grep,Glob,Bash(gh pr view:*),Bash(gh pr diff:*),Bash(gh pr comment:*),Bash(git log:*),Bash(git diff:*),mcp__github_inline_comment__create_inline_comment"
            --append-system-prompt "回答は日本語で行う。ファイル名・識別子・コード片は原文のまま引用する。コードの変更は行わず、方針の説明と該当箇所の提示に留める。"
```

### 6.7 使い方

| やりたいこと | 操作 |
|---|---|
| 通常のレビュー | PR を作成する（自動で走る） |
| 修正後の再レビュー | PR に `@claude この PR をもう一度レビューして` とコメント |
| 指摘内容の質問 | PR に `@claude この指摘の意図を詳しく説明して` とコメント |
| 観点を絞った確認 | PR に `@claude マイグレーションの後方互換性だけ見て` とコメント |
| 指摘の修正 | **ローカルの Claude Code で行う**（[6.3](#63-ジョブ仕様) の権限方針） |

---

## 7. CLAUDE.md と Workflow の役割分担

指示の置き場所を誤ると、レビュー用の指示が日常の実装セッションにまで適用される。`CLAUDE.md` は**そのリポジトリでの全 Claude Code セッションに読み込まれる**ため、レビュー固有の指示を書いてはならない。

| 置き場所 | 書くもの | 判断基準 |
|---|---|---|
| `CLAUDE.md` | 技術スタック、TDD 方針、`current_user` 起点のユーザー分離、命名規約、テストの必須化、マイグレーション方針 | **リポジトリで作業する全セッションに効くべき規約** |
| Workflow / prompt | 出力言語、コメント投稿先、コード編集の禁止、トリガー条件 | **レビューという実行文脈にだけ効くべき指示** |

`REVIEW.md`（レビュー専用の指示ファイル）は**マネージド Code Review 専用**であり、claude-code-action もローカルの `/code-review` も読まない。本リポジトリでは作成しない。

なお、レビューで検出したい項目は `CLAUDE.md` に**明記されていなければ検出されない**（[4.1](#41-プラグインの挙動確認済み) の除外リスト）。特にテストの欠落は既定で除外対象のため、TDD を運用するなら `CLAUDE.md` に必ず書く。

---

## 8. 既存運用への統合

以下は本仕様で定める変更内容であり、**本ドキュメント作成時点では未適用**。

### 8.1 `docs/branching-rules.md` の改訂

7.1 節の標準作業フローに、PR 作成後の待ち工程を追加する。

```diff
  # 6. CI が green になるのを待つ
+
+ # 6b. Claude の自動レビューコメントを読み、対応要否を判断する
+ #     指摘は確信度 80 以上に絞られているが、採否は必ず自分で判断する
+ #     修正後に再レビューが必要なら PR に「@claude もう一度レビューして」とコメント
  
  # 7. Squash merge（CI green 後）
```

7.2 節「PR の運用」に以下を追加する。

- Claude のレビューコメントを確認したうえでマージする。**AI の指摘は一次チェックであり、採否は必ず自分で判断する**。指摘が誤っている場合はその旨を PR に記録し、鵜呑みにしない
- 自動レビューが失敗した場合（認証エラー・タイムアウト等）は、`@claude review` で再実行するか、ローカルで `/code-review` を実行して代替する
- **「No issues found」で終わった場合も、差分の自己確認は省略しない**

9章「dependabot PR の扱い」に以下を追記する。

- dependabot の PR には Secret が渡らないため自動レビューは走らない。従来どおりローカルでのテストと `bundler-audit` / `bundle check` で確認する

11章に本ドキュメントへの参照を追加する。

### 8.2 `.github/pull_request_template.md` の改訂

```diff
  ## 確認したこと
  - [ ] `bundle exec rspec` が green
  - [ ] `bin/rubocop` が green
  - [ ] 差分を自分で一読した
+ - [ ] Claude のレビュー結果を確認した（指摘に対応した、または対応不要と判断した理由を記載した）
```

---

## 9. セキュリティ設計

| 論点 | 評価 | 対応 |
|---|---|---|
| Public リポジトリで第三者が `@claude` を悪用し、サブスク枠を消費される | action 側で対策済み。公式 `docs/security.md` に「The action can only be triggered by users with write access to the repository」と明記 | 追加対応なし。`allowed_non_write_users` は**設定しない** |
| Bot によるトリガー | 既定で GitHub App / Bot はトリガーできない | `allowed_bots` を**設定しない**（特に `'*'` は設定しない） |
| プロンプトインジェクション | PR 本文やコメントに隠し指示が埋め込まれるリスク。action は HTML コメント・不可視文字・画像 alt 等をサニタイズするが完全ではないと公式に明記 | ソロ開発のため外部入力は実質自分の書いたものに限られる。将来外部から PR を受ける場合は `include_comments_by_actor` による許可リスト運用を検討する |
| Secret の露出 | ワークフローファイルは Public だが Secret 値は含まれない。fork PR / dependabot PR には Secret が渡らない | `${{ secrets.* }}` 参照のみとし直書きを禁止（[5.3](#53-取り扱い規約)） |
| `pull_request_target` の使用 | fork PR で Secret にアクセスできてしまう危険なトリガー | **使用しない**。fork PR は [6.5](#65-スキップ条件) でスキップする |
| **Claude App のトークンがワークフローの `permissions:` より広い** | **事実。**`permissions:` が絞るのは自動生成の `GITHUB_TOKEN` であり、Claude App が発行するトークンは App のインストール権限（actions / checks / code / discussions / issues / pull requests / **repository hooks** / **workflows** の read & write ほか）をそのまま持つ。公式 `docs/security.md`「The token cannot access other repositories or perform actions beyond the configured permissions」の *configured permissions* は App 側の設定を指す | **ツールの制限で担保する。** `auto-review` はプラグインの `allowed-tools` により `gh pr/issue` 系と `gh search` のみで、`gh api` もファイル書き込みも不可。`mention` はワークフロー側で `--allowedTools` を明示指定（[6.6](#66-ワークフロー定義)）。権限を最小化したい場合は自作 GitHub App を使う（`docs/setup.md`「Your app's token will have the exact permissions you configured, nothing more」） |
| Claude による意図しないコード変更 | ジョブ権限は両方とも `contents: read` だが、上記のとおり App トークンには依存しない | 実効的な担保はツール制限。`auto-review` はファイル編集ツールを持たず、`mention` も `Read` / `Grep` / `Glob` の読み取り系に限定 |
| 外部マーケットプレイスからのプラグイン取得 | `plugin_marketplaces` に指定した Git URL からコードを取得して実行する | 指定先を `https://github.com/anthropics/claude-code.git`（Anthropic 公式）に限定する。サードパーティのマーケットプレイスは追加しない |

---

## 10. コストと利用枠

| 項目 | 見込み |
|---|---|
| GitHub Actions 実行時間 | **無料**（Public リポジトリの標準ランナー） |
| API 従量課金 | **なし**（OAuth トークンによるサブスク認証のため） |
| Claude Max 5x の利用枠 | 消費する。**消費量は未実測**（→ [12.2](#122-検証項目) No.5） |

### 10.1 消費量に関する注意

1回のレビューで起動するエージェントは、**haiku 2体 ＋ sonnet 3体 ＋ opus 2体 ＋ 指摘ごとの検証サブエージェント N 体**である。単発プロンプトによるレビューより確実に重く、想定より枠を圧迫する可能性がある。

同一アカウントのトークンを使うため、GitHub Actions での消費がローカルの Claude Code 利用枠と共有されると推測されるが、合算方法の明記は公式ドキュメントに見つかっておらず**未確認**（→ [16.4](#16-未確認事項)）。

**この不確実性が、PoC を先行させる主な理由である。** 消費が過大と判明した場合の対応は [12.5](#125-撤退基準と撤退先) に定める。

---

## 11. 導入手順

### 11.1 Phase 0: `CLAUDE.md` の整備

**レビュー方式に依存せず先に実施する。** 4エージェント中2つが `CLAUDE.md` を参照するため、これがない状態で PoC を行うとプラグインを不当に低く評価してしまう。また日常の実装セッションにも即座に効く。

- [ ] 11.1.1 リポジトリ直下に `CLAUDE.md` を作成する（[7章](#7-claudemd-と-workflow-の役割分担)の役割分担に従う）
- [ ] 11.1.2 テストの必須化を明記する（既定では除外対象のため）
- [ ] 11.1.3 `docs/branching-rules.md` との重複を整理し、詳細は参照に留める
- [ ] 11.1.4 PR を作成してマージする

### 11.2 Phase 1: ワークフローの導入

- [ ] 11.2.1 ローカルで `claude setup-token` を実行し、OAuth トークンを発行する
- [ ] 11.2.2 GitHub の Settings → Secrets and variables → Actions に `CLAUDE_CODE_OAUTH_TOKEN` を登録する
- [ ] 11.2.3 Claude GitHub App（https://github.com/apps/claude ）を `workout_tracker` にインストールする。権限は Contents / Issues / Pull requests の Read & Write
- [ ] 11.2.4 トピックブランチ `ci/claude-pr-review` を作成する
- [ ] 11.2.5 `.github/workflows/claude-review.yml` を [6.6](#66-ワークフロー定義) の内容で作成する
- [ ] 11.2.6 `docs/branching-rules.md` を [8.1](#81-docsbranching-rulesmd-の改訂) のとおり改訂する
- [ ] 11.2.7 `.github/pull_request_template.md` を [8.2](#82-githubpull_request_templatemd-の改訂) のとおり改訂する
- [ ] 11.2.8 PR を作成し、**この PR 自体で [12.2](#122-検証項目) No.1〜4 を確認する**
- [ ] 11.2.9 マージする

### 11.3 Phase 2: PoC の実施

- [ ] 11.3.1 [12章](#12-poc実証)を実施する
- [ ] 11.3.2 結果に基づき本仕様を確定させる（v3.0 へ改訂）、または [12.5](#125-撤退基準と撤退先) に従って撤退する

> 11.2.3 の GitHub App インストールは、ローカルの Claude Code で `/install-github-app` を実行して対話的に行うこともできる。ただしこのコマンドは既定で `ANTHROPIC_API_KEY` を前提とした手順を案内するため、Secret 名は本仕様の `CLAUDE_CODE_OAUTH_TOKEN` に読み替える。手動でのインストールでも同等である。

---

## 12. PoC（実証）

本仕様はプラグイン方式を採用しているが、**未検証の前提の上に成り立っている**。本章の検証を経て確定させる。

### 12.1 実施規模

`plan.md` の 2.4〜3.x で発生する **3〜5 PR** ＋ [12.3](#123-検証用-pr既知欠陥の仕込み) の検証用 PR 1本。

期間ではなく PR 件数で区切る。このリポジトリは 2026-07-31 に 4 PR を出すペースであり、暦日での区切りは実態に合わないため。

### 12.2 検証項目

| # | 検証内容 | 確認方法 | 判定基準 | 優先度 |
|---|---|---|---|---|
| 1 | **`--comment` の要否と引数形式** | **ワークフロー導入 PR をマージした後、次の PR で**総評コメントが投稿されるか（→ [12.6](#126-ワークフロー変更を含む-pr-では検証できない)） | 投稿される。されない場合は引数形式を変えて再試行（[12.2.1](#1221---comment-の検証手順)） | **最優先** |
| 2 | 対象 PR の指定形式が解釈されるか | ジョブログで、正しい PR 番号のレビューが行われているか | 対象を取り違えていない | 最優先 |
| 3 | 日本語で出力されるか | 投稿されたコメントの言語 | 総評・インラインとも日本語 | 高 |
| 4 | インラインコメントが投稿されるか | PR の Files changed タブ | 該当行にコメントが付く（[5.4](#54-既知の制約) の未確認事項の検証を兼ねる） | 高 |
| 5 | 利用枠の消費量 | 1レビューあたりの体感消費、ローカル作業への影響 | ローカル作業に支障が出ない | 高 |
| 6 | 実行時間 | ジョブの所要時間 | 30 分のタイムアウト内に収まる | 中 |
| 7 | `track_progress` 無効化が妥当か | skip されずレビューが完走するか | 自己コメントによる skip が起きない | 中 |
| 8 | ツール権限のエラーが出ないか | ジョブログ | 権限エラーで処理が止まらない | 中 |

#### 12.2.1 `--comment` の検証手順

プラグインのコマンド定義（L63）は「`--comment` が指定されていなければ、ここで停止し GitHub コメントを一切投稿しない」と明記している。一方、**公式ドキュメントの GitHub Actions 例では `--comment` が省略されている**。この矛盾は未解決であり、公式例をそのまま使うと**レビューは完走するが PR には何も投稿されず、ジョブは成功扱いで終わる**。

コマンド定義に `$ARGUMENTS` プレースホルダは存在せず、引数の解釈はモデル任せであるため、記述順も保証されていない。次の順に試す。

1. `/code-review:code-review <owner/repo>/pull/<N> --comment`（本仕様の既定）
2. `/code-review:code-review --comment`（対象を省略。PR ブランチが checkout 済みのため解決される可能性）
3. `/code-review:code-review --comment <owner/repo>/pull/<N>`（順序を入れ替え）

いずれでも投稿されない場合は、プラグイン方式を撤退の対象とする（[12.5](#125-撤退基準と撤退先)）。

### 12.3 検証用 PR（既知欠陥の仕込み）

検出率・見逃しを測るには正解が必要なため、**意図的に既知の欠陥を含む PR を1本作成する**。マージはせず、検証後にクローズする。

| # | 仕込む欠陥 | 期待 | 測るもの |
|---|---|---|---|
| 1 | `current_user` 起点でないリソース取得（例: `Workout.find(params[:id])`） | 検出されるべき | ユーザー分離の検出率。`CLAUDE.md` に明記した規約が機能するか |
| 2 | `authenticate_user!` の付け忘れ | 検出されるべき | 認証漏れの検出率 |
| 3 | 明らかな nil 参照や論理誤り | 検出されるべき | バグ検出エージェントの基礎性能 |
| 4 | 明らかな N+1 | 要観測 | 「入力に依存する問題」として除外されるかの確認 |
| 5 | 新規メソッドに対する spec 欠落 | **`CLAUDE.md` に明記があれば検出、なければ非検出** | `CLAUDE.md` の記述が検出結果を変えることの実証 |

5 は `CLAUDE.md` の該当記述を一時的に外した状態と入れた状態の両方で試すと、`CLAUDE.md` 設計への直接のフィードバックになる。

> **注意**: この PR は既知の脆弱パターンを含むため、**絶対にマージしない**。検証後は速やかにクローズし、ブランチを削除する。

### 12.4 評価軸

「指摘なし率」だけでは受動的な観察に留まるため、以下の6軸で評価する。

| # | 評価軸 | 測定方法 | 合格の目安 |
|---|---|---|---|
| 1 | **既知問題の検出率** | [12.3](#123-検証用-pr既知欠陥の仕込み) の欠陥 1〜3 のうち検出された数 | 3件中2件以上 |
| 2 | **誤検知** | 通常 PR で指摘されたもののうち、対応不要と判断した件数 | 全指摘の 1/3 未満 |
| 3 | **見逃し** | 自分でレビューして見つけた問題のうち、Claude が指摘しなかったもの | 重大な見逃しがゼロ |
| 4 | **学習価値** | 指摘を読んで新しく学べたことがあったか（PR ごとに主観で3段階） | 半数以上の PR で「あり」 |
| 5 | **不適切な skip** | レビューされるべき PR がスキップされた件数。特に小規模 PR（PR #10 相当の +25/-3 規模）での発生 | ゼロ |
| 6 | **投稿成功率** | レビューが完走した PR のうち、総評・インラインが実際に投稿された割合 | 100%（1件でも欠ければ No.1・No.4 の再検証） |

### 12.5 撤退基準と撤退先

#### 撤退基準

以下のいずれかに該当した場合、プラグイン方式を撤退する。

| # | 条件 |
|---|---|
| 1 | [12.2.1](#1221---comment-の検証手順) の全パターンで PR に投稿されない |
| 2 | 利用枠の消費が過大で、ローカルの実装作業に支障が出る |
| 3 | 評価軸 No.1（検出率）が 3件中1件以下 |
| 4 | 評価軸 No.5（不適切な skip）が頻発し、小規模 PR がレビューされない |
| 5 | 評価軸 No.4（学習価値）が「あり」の PR が半数を大きく下回り、「No issues found」ばかりになる |

#### 撤退先

**手書きプロンプト方式**（本仕様書 v1.0）に戻す。完全なワークフロー定義は次のコミットに保存されている。

```
commit 7918fcf64f57ee6015ea18e936d912e30b182bdb
  docs: add PR review automation spec (hand-written prompt variant)
  → 6.6 節にワークフロー定義の全文
```

このコミットは squash マージで `main` の履歴には含まれないため、次のいずれかで参照する。

```bash
# ローカル（タグ経由。推奨）
git show pr-review-spec-v1:docs/pr-review-automation.md

# ローカルに無い場合は GitHub の PR ref から取得する
git fetch origin refs/pull/12/head
git show 7918fcf:docs/pr-review-automation.md
```

手書き方式の特徴（撤退時の判断材料）:

| | プラグイン方式（本仕様） | 手書き方式（v1.0） |
|---|---|---|
| 構成 | 多エージェント＋裏取り、確信度 80 で足切り | 単一エージェント |
| 検出方針 | 高シグナル特化。些末な指摘・テスト欠落・一般的品質懸念は既定で除外 | 🔴要修正 / 🟡改善提案 / 🟣既存の問題 の3段階で、学習向けの指摘も拾う |
| 観点の置き場所 | `CLAUDE.md` | ワークフローのプロンプト（53行） |
| 保守 | プラグイン更新に追随（自動） | 自分で育てる |
| 消費 | 重い（未実測） | 軽い |
| `synchronize` | 使えない（重複 skip のため） | 使える |

撤退条件 5（静かすぎる）で撤退する場合は、**プラグイン（バグ検出）＋ 手書き（学習向け改善提案）の二段構成**も選択肢になる。ただし枠の消費は加算されるため、撤退条件 2 と両立しない場合は手書き単独とする。

### 12.5b 第1回検証の結果（2026-08-04）

ローカルでの実行と GitHub Actions での実行で結果が分かれた。

| 経路 | 結果 |
|---|---|
| ローカル（`claude -p "/code-review:code-review <owner/repo>/pull/14 --comment"`） | **成功。** PR #14 に総評コメントを投稿 |
| GitHub Actions | **失敗。** `is_error: true` / `duration_ms: 78` / `num_turns: 1` |

確定した事項:

- **`--comment` は必要かつ有効**（[16.1](#16-未確認事項) を解決）。省略するとプラグイン定義 L63 のとおり投稿されない
- 対象指定形式 `owner/repo/pull/N` は解釈される（[16.2](#16-未確認事項) を解決）
- **指摘ゼロ時の総評は日本語にならない。** プラグイン定義 L93〜99 が `No issues found. Checked for bugs and CLAUDE.md compliance.` という固定英文を投稿する仕様のため。指摘がある場合に日本語化が効くかは未確認

Actions 側の失敗について切り分けた結果:

- 認証は原因ではない（トークンを再発行・再登録しても同じ signature）
- コマンド未解決も原因ではない（未解決の場合は `is_error: false` / `num_turns: 0` / `duration_ms: 8` で「Unknown command」を返す。実測で確認）
- 初期化から結果まで 29ms しかなく、API への往復が発生していない。**プロセス内での失敗**
- エラー本文は action が伏せるため未特定（`Running Claude Code via SDK (full output hidden for security)`）

#### 原因（2026-08-04 特定・解決済み）

`show_full_output: true` を一時的に有効にして取得したエラー本文は次のとおりだった。

```
"result": "API Error: Header 'Authorization' has invalid value: '***'"
"terminal_reason": "api_error"
```

**`Authorization` ヘッダの値が不正で、HTTP クライアントが送信前に拒否していた。** ネットワーク往復が発生しないのはこのためであり、サーバによる認証拒否（401）ではなかった。原因は Secret に登録したトークン文字列への**改行・空白の混入**。ブラウザからの貼り付けでは末尾の改行を目視できないため、次の方法で再登録して解決した。

```bash
printf '%s' "$(pbpaste)" > /tmp/claude_token   # $(...) が末尾改行を除去する
cat -A /tmp/claude_token | tail -c 60          # 末尾に `$` が出ないことを確認
gh secret set CLAUDE_CODE_OAUTH_TOKEN --repo <owner>/<repo> < /tmp/claude_token
rm /tmp/claude_token
```

> **教訓**: トークンを Secret に登録する際はブラウザの貼り付けを避ける。症状は「認証エラー」ではなく「即座に終わるプロセス内エラー」として現れるため、原因にたどり着きにくい。

#### 実測値（2026-08-04・PR #14 を対象）

| 項目 | 値 |
|---|---|
| 実行時間 | **10分24秒** |
| ターン数 | 34 |
| 消費（換算） | **$3.05** |
| 指摘 | 1件（検証パスを通過） |

[16.4](#16-未確認事項)（枠の消費）の基礎データとなる。**1 PR あたり約 $3 相当**をサブスク枠から消費する。

#### `--max-turns` の実測値と上限（2026-08-07）

| run | 対象 | 結果 | ターン数 | 消費 |
|---|---|---|---|---|
| 31143697626 | PR #19 初回 | success | 17 | $1.05 |
| 31145098701 | PR #19 再実行 | success | 27 | $2.79 |
| 31155953302 | PR #21 | **`error_max_turns`** | **31（上限 30 に到達）** | $1.15 |

**打ち切られた実行は投稿を1件も行わない。** ジョブは failure で終わるため気づけるが、レビュー結果は失われる。

ターン数は差分の規模ではなく**指摘候補の数**に影響される。プラグインは skip 判定・`CLAUDE.md` 収集・差分要約・4エージェント並列レビュー・指摘ごとの検証サブエージェント・投稿とサブエージェントを多数起動し、そのそれぞれがターンを消費するため、小さな差分でもターン数が伸びうる。

このため上限を **30 → 60** に引き上げた。`--max-turns` は上限であって予算ではなく、引き上げても平均消費は増えない（打ち切られた実行は $1.15 で、成功した27ターンの実行 $2.79 より安い）。暴走に対する歯止めは `timeout-minutes: 30` が担う。

> 策定時に「`--max-turns` を 8〜10 に下げるべき」という助言を検討し、「下げても平均消費は減らず、長い実行が途中で打ち切られるだけ」として退けた（当時 20 → 30 に引き上げ）。今回はその予測どおりの事象が起きたが、30 でも不足していた。

#### 検証時に判明した制約: `workflow_dispatch` では投稿できない

診断のため一時的に追加した `workflow_dispatch` 経由で実行した場合、レビューは完走するが**コメントを投稿できない**。

- インラインコメント用の MCP ツールは action が PR コンテキストから初期化するため、PR イベントではない `workflow_dispatch` では提供されない
- フォールバックで `gh api`（write）を使おうとするが、プラグインの `allowed-tools` に含まれないため遮断される
- また checkout がデフォルトブランチになるため、リポジトリのファイルを読むエージェントは PR ブランチではなく `main` の内容を見る

いずれも `pull_request` イベント経由では発生しない。**`workflow_dispatch` は診断専用であり、常設しない。**

### 12.6 ワークフロー変更を含む PR では検証できない

action は実行前にワークフローファイルを検証し、**デフォルトブランチ上の内容と一致しない場合は処理をスキップする**（PR #13 で確認）。ジョブは `success` で終わり、10秒程度で完了するため、ログを見ないと「レビューが走ったが指摘ゼロだった」と誤認しやすい。

```
Skipping action due to workflow validation: The workflow file must exist and have
identical content to the version on the repository's default branch.
```

このため次の制約がある。

- **ワークフロー導入 PR 自身では `--comment` を検証できない。** マージ後の最初の PR が実質的な第1回検証になる
- **今後 `claude-review.yml` を変更する PR には、レビューが付かない。** 変更をマージした次の PR から反映される
- ジョブが数秒で `success` になった場合は、まずこのスキップを疑う

---

## 13. レビュー品質の振り返り

AI レビューは導入して終わりではなく、運用しながら精度を上げていく必要がある。PoC 完了後も、以下を継続する。

### 13.1 日常の記録（コストをかけない）

- Claude のレビューコメントに **👍 / 👎 のリアクション**を付ける。役に立ったか否かの記録がそれだけで残る
- 対応しなかった指摘は、PR にその理由を1行書く

### 13.2 定期的な棚卸し

`plan.md` の区切り（各章の完了時、および 12.2「テスト・静的解析の全体実行」）のタイミングで振り返る。

| 見るもの | アクション |
|---|---|
| 👎 が付いた指摘の傾向 | **プロンプトではなく `CLAUDE.md` の記述の曖昧さを先に疑う**。プラグインは確信度 80 で足切りしているため、誤検知の多くは規約の書き方に起因する |
| 見逃した問題の傾向 | 該当する規約が `CLAUDE.md` にあるか確認し、なければ追記する |
| 「No issues found」の割合 | 高すぎる場合は `CLAUDE.md` に具体的な規約を足す。それでも変わらなければ [12.5](#125-撤退基準と撤退先) の二段構成を検討する |
| 消費量 | 過大なら対象 PR を絞る（`paths-ignore` で `docs/**` `plans/**` のみの変更を除外する等） |

### 13.3 記録場所

本ドキュメントの [18章](#18-振り返り記録)に追記する。

---

## 14. リスクと対応

| リスク | 可能性 | 影響 | 対応 |
|---|---|---|---|
| `--comment` の解釈が異なり、レビューが投稿されない | **高** | 高 | [12.2.1](#1221---comment-の検証手順) を最優先で実施。11.2.8 の PR で即座に判明する |
| 利用枠を想定以上に消費する | 中 | 高 | [12.4](#124-評価軸) No.5 で測定。撤退基準 2 |
| 高シグナル特化のため指摘が少なすぎ、学習効果が出ない | 中 | 中 | 評価軸 No.4 で測定。撤退基準 5。`CLAUDE.md` の具体化で改善できる可能性がある |
| 小規模 PR が trivial 判定でスキップされる | 中 | 中 | 評価軸 No.5 で測定。PR #10 は +25/-3 と小さく、該当しうる |
| OAuth トークンの失効により自動レビューが止まる | 中 | 中 | 認証エラーはジョブ失敗として PR の Checks に現れる。失敗を見つけたら再発行する（[5.2](#52-トークン発行手順)） |
| プラグインの仕様変更に追随できない | 低 | 中 | プラグインは Anthropic 公式リポジトリで管理されている。挙動が変わったら本仕様の [4.1](#41-プラグインの挙動確認済み) を更新する |
| AI の誤指摘に従って不要な変更を入れる | 中 | 中 | 「採否は必ず自分で判断する」を運用ルールに明記（[8.1](#81-docsbranching-rulesmd-の改訂)）。修正権限を与えない（[6.3](#63-ジョブ仕様)） |
| レビューの存在に安心して差分を自分で読まなくなる | 中 | 高 | PR テンプレートの「差分を自分で一読した」項目を維持する。「No issues found」でも自己確認を省略しないと明記（[8.1](#81-docsbranching-rulesmd-の改訂)） |
| Public リポジトリでの第三者トリガー | 低 | 中 | action 側で書き込み権限チェック済み（[9章](#9-セキュリティ設計)） |

---

## 15. ロールバック方針

| 対象 | 手順 |
|---|---|
| ワークフロー | `.github/workflows/claude-review.yml` を削除して push する。以後レビューは走らない |
| 手書き方式への差し戻し | `git show 7918fcf:docs/pr-review-automation.md` から 6.6 節を復元する |
| ドキュメント | `docs/branching-rules.md` / `.github/pull_request_template.md` / `CLAUDE.md` の変更を revert する |
| Secret | Settings → Secrets and variables → Actions から `CLAUDE_CODE_OAUTH_TOKEN` を削除する |
| GitHub App | Settings → GitHub Apps → Claude → Configure からリポジトリのアクセスを外す、またはアンインストールする |
| DB 変更 | **DB 変更なし** |

不可逆な変更は含まれない。ワークフローファイルの削除だけでレビューは即座に停止する。

---

## 16. 未確認事項

優先度順。判明したら本ドキュメントを更新する。

| # | 内容 | 影響 | 確認タイミング |
|---|---|---|---|
| ~~16.1~~ | ~~`--comment` の要否と引数形式~~ | — | **解決済み（2026-08-04）。`--comment` は必要。公式 Actions 例の省略は記載漏れと判断してよい**（[12.5b](#125b-第1回検証の結果2026-08-04)） |
| 16.2 | `claude setup-token` で発行されるトークンの有効期限 | 突然レビューが止まる | 運用中に認証エラーが出た時点 |
| 16.3 | OAuth トークン使用時のインラインコメント投稿の可否 | インライン投稿されず総評のみになる可能性 | **未確認のまま**。PR #19 で投稿されなかったのは `--allowedTools` の欠落が原因であり OAuth とは別問題。修正をマージした次の PR で確認する |
| 16.4 | GitHub Actions での消費が Max の枠とどう合算されるか | 枠の圧迫 | 実測は **1 PR あたり10分24秒・$3.05 相当・34ターン**（[12.5b](#125b-第1回検証の結果2026-08-04)）。ローカル利用枠との合算方法は依然**未確認** |
| 16.5 | `--append-system-prompt` の日本語指定が、サブエージェントを含む最終出力まで効くか | 英語で投稿される可能性 | **指摘ゼロ時は効かない**（プラグイン定義 L93〜99 の固定英文）。実測されたレビュー本文自体は日本語だった。投稿された状態での確認は未実施 |
| 16.6 | `track_progress` の進捗コメントがプラグインの skip 判定を誤爆させるか | 本仕様では無効化して回避済み。有効化したい場合に要検証 | [12.2](#122-検証項目) No.7 |
| ~~16.7~~ | ~~プラグイン側 `allowed-tools` とワークフロー側 `--allowedTools` の優先関係~~ | — | **解決済み（2026-08-07）。両者は独立で、action が見るのはワークフロー側だけ。両ジョブとも明示指定が必須**（[4.2](#42-この挙動から導かれる設計上の帰結)） |
| 16.8 | 「🔴 要修正が残っていたらマージをブロック」の実現方法 | — | [17.2](#172-マージゲート化) を検討する時点 |
| 16.9 | `mention` ジョブの `--allowedTools` が実用に足りるか（絞りすぎて回答できないことがないか） | 質問に答えられない | [12.2](#122-検証項目) No.9 / フェーズ6のメンション試行 |
| 16.10 | Secret に登録するトークンへの改行・空白混入 | **`Authorization` ヘッダ不正で即座に失敗する。エラーが伏せられるため原因特定が難しい** | 発生済み・解決済み。再登録時は [12.5b](#125b-第1回検証の結果2026-08-04) の手順を使う |

---

## 17. 将来の拡張

### 17.1 ローカル `/code-review` との併用

Claude Code には `/code-review` コマンドがあり、push 前にローカルで差分をレビューできる。CI に出す前の一次チェックとして併用でき、`docs/branching-rules.md` 11.3 が定める「ローカル品質チェックと CI の二層」の考え方と整合する。本仕様の代替ではなく補完として位置づける。

### 17.2 マージゲート化

`auto-review` ジョブを Ruleset の必須ステータスチェックに追加すると、「レビューが走っていない PR はマージできない」状態を構造的に作れる。

ただしこれで担保できるのは「レビューが実行されたこと」までで、「重大な指摘が残っていないこと」をマージ条件にするには、レビュー結果を機械可読な形で出力し判定する追加実装が必要となる。実現方法は**未確認**（[16.8](#16-未確認事項)）。

PoC が完了し、レビューの所要時間と品質が把握できるまでは導入しない。レビュー待ちで作業が止まり、単独開発のテンポを損なう可能性があるため。

---

## 18. 振り返り記録

[13章](#13-レビュー品質の振り返り)に基づく記録を追記する。

- なし

---

## 19. 参照

- [Claude Code GitHub Actions（公式ドキュメント）](https://code.claude.com/docs/en/github-actions)
- [anthropics/claude-code-action](https://github.com/anthropics/claude-code-action)
  - `docs/setup.md` — 認証方式
  - `docs/security.md` — アクセス制御・プロンプトインジェクション
  - `docs/solutions.md` — 自動 PR レビューの構成例
- [anthropics/claude-code](https://github.com/anthropics/claude-code)
  - `plugins/code-review/commands/code-review.md` — プラグインのコマンド定義（本仕様 [4.1](#41-プラグインの挙動確認済み) の根拠）
  - `plugins/code-review/README.md` — プラグインの概要
- [Code Review（マネージドサービス / Team・Enterprise 限定）](https://code.claude.com/docs/en/code-review)
- [`docs/branching-rules.md`](./branching-rules.md) — ブランチ運用ルール
- リポジトリ直下の `CLAUDE.md` — レビューエージェントが参照する唯一のプロジェクト規約

---

## 変更履歴

- 2.4（2026-08-07）: `--max-turns` を 30 → 60 に引き上げ。PR #21 で `error_max_turns` により投稿0件のまま打ち切られたため。実測値の推移（17 → 27 → 31）と、ターン数が差分規模ではなく指摘候補数に影響される点を 12.5b に記録。

- 2.3（2026-08-07）: **4.2 の設計判断5を訂正。** `--allowedTools` は両ジョブとも必須であり、挙げないとインラインコメント用 MCP サーバが起動せず投稿できない（action のソースで確認）。6.3・16.7 を更新し、16.7 を解決済みに。

- 2.2（2026-08-04）: 第1回検証の結果を 12.5b に記録。`--comment` が必要であること（16.1 を解決）、Actions 側の失敗原因が Secret に混入した改行による `Authorization` ヘッダ不正だったこと、実測値（10分24秒 / $3.05 / 34ターン）、`workflow_dispatch` ではインラインコメント用 MCP が提供されず投稿できないことを追記。診断用設定（`show_full_output` / `--debug` / `workflow_dispatch`）は削除済み。

- 2.1（2026-08-04）: Claude App のトークンがワークフローの `permissions:` では絞られないことが判明したため、9章のリスク評価を訂正し、`mention` ジョブに `--allowedTools` を追加（6.3 / 6.6 / 4.2）。`actions/checkout` を既存 `ci.yml` に合わせて v7 に変更。撤退先コミットの参照方法をタグ `pr-review-spec-v1` 経由に変更（12.5）。

- 2.0（2026-08-03）: 公式 `code-review` プラグイン方式に変更し、PoC 前提の暫定仕様として再構成。`--comment` の未検証を最優先事項に格上げ。`synchronize` を削除（プラグインの重複 skip 仕様のため）。`mention` の権限を `contents: read` に変更。`track_progress` と `--allowedTools` を意図的に無効化。`CLAUDE.md` の整備を Phase 0 として導入手順の先頭へ。PoC 章・評価軸6項目・検証用 PR・撤退基準・振り返り章を追加。手書きプロンプト方式は commit `7918fcf` への参照に置き換え、本文からは削除。なお策定過程で詳細仕様書のリポジトリ内取り込みを検討したが、プラグインが `CLAUDE.md` しか読まないためレビュー内容が変わらず、Public リポジトリへの公開のみが代償として残ることから見送った（[2章](#2-前提条件) / [4.1](#41-プラグインの挙動確認済み)）。
- 1.0（2026-08-03）: 初版策定。GitHub Actions ＋ `claude-code-action@v1` ＋ OAuth トークン認証による、手書きプロンプト方式の自動レビューと `@claude` メンションの併用構成。
