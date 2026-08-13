# ブランチ運用ルール（workout_tracker）

本プロジェクトのブランチ運用ルールを定める。方式は **GitHub Flow** をベースとする。

- 対象リポジトリ: `workout_tracker`（Public / ソロ開発）
- 目的: 現場デファクトの「ブランチ → PR → CI green → main マージ」の型で開発する
- 版: 1.6（2026-08-13 改訂。初版 2026-07-28）

---

## 1. 基本方針

- `main` は**常にデプロイ可能な状態**を保つ。壊れたコードを `main` に入れない。
- 変更は必ず**短命なトピックブランチ**で行い、**PR 経由**で `main` にマージする。
- `main` への**直接 push は禁止**（ブランチ保護で強制する。→ 5章）。
- マージ条件は **CI が green** であること（→ 4章・6章）。
- ソロ開発のため他者レビューは無いが、PR は「CI ゲート」＋「マージ前に自分で差分を読み直す場」として必ず通す。

---

## 2. ブランチ構成

| ブランチ | 役割 | 寿命 |
|---|---|---|
| `main` | 常にデプロイ可能な唯一の統合ブランチ。保護対象 | 永続 |
| トピックブランチ | 1つの作業単位（機能・修正・雑務）。`main` から分岐し PR でマージ後に削除 | 短命（数時間〜数日） |

- `develop` や `release` などの長期ブランチは**作らない**（GitHub Flow のため）。
- トピックブランチは**小さく保つ**。原則 **1トピックブランチ ＝ `plan.md` の1項目、または小さな関連項目の集合**とする。`plan.md` があるため項目を粒度の基準にでき、巨大ブランチになりにくい。1項目が大きい場合は分割する（詳細は11章）。
- 分岐元は常に最新の `main`。作業開始前に `main` を最新化する。

---

## 3. ブランチ命名規約

### 3.1 形式

```
<type>/<short-description>
```

- `<type>`: 変更種別（下表）。Conventional Commits のタイプに対応させる。
- `<short-description>`: 内容がわかる英小文字・数字・ハイフンの短い説明（kebab-case）。
- 仕様の機能ID（F-01 等）がある場合は接頭に含めてよい: `feat/f01-devise-auth`。

### 3.2 type 一覧

| type | 用途 | ブランチ例 |
|---|---|---|
| `feat` | 新機能 | `feat/f01-devise-auth` |
| `fix` | バグ修正 | `fix/webhook-idempotency` |
| `refactor` | 挙動を変えない内部改善 | `refactor/workout-set-query` |
| `test` | テストのみの追加・修正 | `test/user-model-spec` |
| `chore` | 依存更新・設定・雑務 | `chore/bump-rubocop` |
| `docs` | ドキュメントのみ | `docs/branching-rules` |
| `ci` | CI/ワークフロー変更 | `ci/add-rspec-job` |
| `perf` | パフォーマンス改善 | `perf/dashboard-n-plus-one` |

### 3.3 禁止・注意

- `main` への直接コミット禁止。
- 日本語・空白・大文字を含めない（`ignorecase = true` の macOS では特に大小混在を避ける）。
- 使い終わったブランチはマージ後に削除する（PR マージ時に自動削除設定を推奨）。

---

## 4. コミットメッセージ規約（Conventional Commits）

### 4.1 形式

```
<type>(<scope>)?: <subject>

<body（任意）>
```

- `<type>`: 3.2 と同じ語彙（`feat` / `fix` / `refactor` / `test` / `chore` / `docs` / `ci` / `perf`）。
- `<scope>`: 任意。影響範囲（例: `auth`, `webhook`, `dashboard`）。
- `<subject>`: 変更内容を英語・命令形・簡潔に。末尾ピリオドなし。
- 破壊的変更がある場合は `feat!: ...` または body に `BREAKING CHANGE:` を記載。

### 4.2 例

```
feat(auth): add Devise user registration
fix(webhook): dedupe by lineEventId to keep idempotency
test(user): cover name presence and email uniqueness
chore: bump rubocop to 1.x
```

### 4.3 squash マージとの関係

- マージは squash（→ 6章）。**PR タイトルを Conventional Commits 形式にする**と、squash 後の `main` のコミットタイトルがそのまま規約準拠になる。
- 作業中の個々のコミットは厳密でなくてよい（squash で1つにまとまるため）。ただし PR タイトルは必ず規約に従う。

---

## 5. main ブランチ保護（GitHub Ruleset）

Public リポジトリのため **Repository Rulesets** で `main` を保護する（従来の Branch protection でも可だが、GitHub 推奨の Rulesets を採用）。

### 5.1 設定内容

対象ブランチ: `main`

- [x] **Restrict deletions**（`main` の削除禁止）
- [x] **Block force pushes**（force push 禁止）
- [x] **Require a pull request before merging**（PR 必須＝直接 push 禁止）
  - Required approvals: `0`（ソロのため他者承認は不要。CI ゲートで担保）
  - Dismiss stale approvals / require review from Code Owners: 不要
- [x] **Require status checks to pass**（CI green を必須）
  - Require branches to be up to date before merging: **有効**
  - 必須チェック（CI ジョブ名）: `scan_ruby` / `scan_js` / `lint` / **`test`**
    - `test` は RSpec ジョブ（→ 8章で追加）。追加前は選択肢に出ないため、CI を1度走らせてから登録する。
- [x] **Require linear history**（マージコミットを作らず履歴を直線に保つ。squash 運用と整合）

### 5.2 bypass（例外）方針

- Bypass list には原則誰も入れない（自分自身も含め、ルールを実際に守る練習のため）。
- どうしても詰まった場合のエスケープハッチは 7章参照。

---

## 6. マージ方式

- **Squash and merge** に統一する。
  - `main` は「1 PR ＝ 1 コミット」で読みやすく保つ。
  - squash コミットのタイトルは PR タイトル（Conventional Commits）を使う。
- リポジトリ設定で **Squash 以外のマージボタンを無効化**する（Merge commit / Rebase を Off）。
- マージ後は**ブランチを自動削除**する（Settings → General → Automatically delete head branches を有効化）。

---

## 7. 標準作業フロー

### 7.1 手順

```bash
# 1. main を最新化
git switch main
git pull origin main

# 2. トピックブランチを作成
git switch -c feat/f01-devise-auth

# 3. 実装（TDD: RED → GREEN → REFACTOR。plan.md の1ステップ単位）
#    こまめにコミット（メッセージは緩くてOK、squash で集約）
git add -A
git commit -m "feat(auth): add Devise user model"

# 4. push
git push -u origin feat/f01-devise-auth

# 5. PR 作成（タイトルは Conventional Commits 形式にする）
#    gh CLI を使う場合:
gh pr create --fill --base main

# 6. CI が green になるのを待つ

# 6b. Claude の自動レビュー結果を読み、対応要否を判断する
#     指摘は確信度 80 以上に絞られているが、採否は必ず自分で判断する
#     修正後に再レビューが必要なら PR に「@claude もう一度レビューして」とコメント

# 7. Squash merge（CI green 後）
gh pr merge --squash --delete-branch

# 8. ローカルを戻す
git switch main
git pull origin main
```

### 7.2 PR の運用

- PR タイトル: Conventional Commits 形式（例: `feat(auth): add Devise authentication`）。
- 説明: 変更概要・確認したこと（テスト結果等）を簡潔に。テンプレは任意（→ 付録B）。
- **マージ前に自分で Files changed を必ず一読する**（ソロでもレビュー習慣をつける）。
- CI が落ちたら修正コミットを push し、green を待ってからマージ。
- Claude の自動レビュー結果を確認したうえでマージする。**AI の指摘は一次チェックであり、採否は必ず自分で判断する**。指摘が誤っている場合はその旨を PR に記録し、鵜呑みにしない（→ `docs/pr-review-automation.md`）。
- **「No issues found」で終わった場合も、差分の自己確認は省略しない。** レビューは追加の層であり、自分で読むことの置き換えではない。
- 自動レビューが失敗した場合（認証エラー・タイムアウト等）は、PR に `@claude review` とコメントして再実行するか、ローカルで `/code-review` を実行して代替する。
- 自動レビューは PR 作成時に1回だけ走る（`synchronize` は使わない）。修正後の再レビューが必要なら、PR を **close → reopen** する（`reopened` で再実行される）。
- **`auto-review` が数十秒で終わり、投稿が1件もない場合はスキップされている。** プラグインは「些末で明らかに正しい変更」と判断した PR をスキップする仕様で、**その場合もジョブは success で終わる**ため、投稿の有無を見ないと「指摘なし」と区別がつかない。レビューが必要なら close → reopen するか、ローカルで実行する（→ `docs/pr-review-automation.md`）。
- **`@claude` メンションは質問用途に使う。** 「レビューして」と依頼すると、プラグインを経由しない素の Claude Code が許可外ツールを試みてターンを浪費し、打ち切られることがある。レビューは `auto-review` の役割。

### 7.3 エスケープハッチ

- ルールで詰んで前に進めない場合のみ、一時的に Ruleset を Disable して対応し、**対応後すぐ Enable に戻す**。常用しない。

---

## 8. CI との関係（RSpec テストジョブの追加）

「CI green を必須」を実効化するため、現状の CI（`scan_ruby` / `scan_js` / `lint`）に **RSpec を実行する `test` ジョブ**を追加する。

- PostgreSQL を service コンテナで起動し、`db:test:prepare` 後に `bundle exec rspec` を実行する。
  - `db:prepare` を使わないこと。DB 新規作成時に seed も実行されるため、テスト DB にプリセットが混入し、空の DB を前提とする spec が落ちる（PR #29 で発生）。`db:test:prepare` は schema のみロードし seed を実行しない。
- 追加後、必須ステータスチェックに `test` を登録する（5.1）。
- ジョブ定義の参考は付録A。

> 注: 本ジョブ追加は別作業（`.github/workflows/ci.yml` の変更）。本ドキュメントでは方針と参考定義のみ示す。

---

## 9. dependabot PR の扱い

- `dependabot.yml` により bundler / github-actions の更新 PR が weekly で作成される。
- これらも通常 PR と同じく **CI green を確認してから squash merge** する。
- 破壊的な更新やロックファイル大量変更は、ローカルでテストを回してからマージする。
- **dependabot の PR には自動レビューは走らない。** dependabot が起動した `pull_request` イベントには Actions Secret が渡らず、必ず認証エラーになるため、ワークフロー側で明示的に除外している。従来どおりローカルでのテストと `bundler-audit` / `bundle check` で確認する（→ `docs/pr-review-automation.md` 6.5）。

---

## 10. 適用手順（このルールを実運用に落とすまで）

- [ ] GitHub にリモートリポジトリ（Public）を作成し `main` を push する
- [ ] Settings → General: Squash のみ許可 / head branch 自動削除を有効化
- [ ] `.github/workflows/ci.yml` に `test`（RSpec）ジョブを追加する（付録A）
- [ ] CI を1度走らせて `test` チェックを実体化させる
- [ ] Settings → Rules → Rulesets: 5章の内容で `main` 保護を作成・Enable
- [ ] テスト用ブランチで PR → CI → squash merge を1周通し、保護が効くことを確認

---

## 11. TDD 開発ワークフロー（tdd-dev）との関係

本ルールと `tdd-dev` スキルはレイヤーが異なり、併用する。

- **本ルール（branch）**: 変更を「どう束ね、どう `main` に入れるか」（ブランチ・PR・CI・マージ）
- **`tdd-dev`**: 1つの作業項目を「どう実装するか」（RED → GREEN → REFACTOR、品質・セキュリティチェック）
- **`plan-checklist`**: 計画ファイルの作成と記録形式（チェックボックス・検証記録・問題履歴）
- **`docs/pr-review-automation.md`**: PR に自動レビューを走らせる基盤（GitHub Actions ＋ Claude Code の公式 `code-review` プラグイン）。本ルールの「PR ＝ CI ゲート＋自分で差分を読む場」という位置づけに、機械的なレビュー層を1つ足すもの。レビューが参照する規約はリポジトリ直下の `CLAUDE.md` に置く

### 11.1 ブランチの粒度 ＝ plan.md の項目単位

- `tdd-dev` は「`plan.md` の未完了項目を1つずつ」実装する。これに合わせ、トピックブランチは原則 **`plan.md` の1項目、または小さな関連項目の集合 ＝ 1ブランチ ＝ 1PR** を基準にする（2章の粒度基準。例: `plan.md` の `2.2b User モデルの実装` → `feat/f01-user-model`）。
- 大きすぎる項目を `tdd-dev` の「作業分解（補助サブ項目）」で分割した場合も、**ブランチ／PR は元の項目単位のまま**にする（振る舞い単位ごとにブランチを切らない）。1ブランチ内で複数回 RED → GREEN → REFACTOR を回し、まとめて1PRにする。
- 項目が大きく PR が肥大化する場合のみ PR を分割してよい。ただし「PR は小さく保つ」原則（2章）を優先する。

### 11.2 コミット粒度と squash マージの関係

- 作業中のコミットは緩くてよい（4.3）。RED → GREEN → REFACTOR の途中経過はこまめにコミットしてよく、squash マージで `main` には**項目単位の1コミット**として残る。
- `plan.md` のチェックボックス更新・検証記録（`plan-checklist` 形式）は、**その項目のブランチ内でコミットする**（別ブランチに切り出さない）。計画ファイルの更新も PR に含めて1つの単位にする。
- コミット・push は**依頼された場合のみ**行う（`tdd-dev` / `plan-checklist` / 個人ルール共通）。AI が無断でコミット・push・マージはしない。ブランチ運用の各操作は原則ユーザーが実行する。

### 11.3 マージ条件とローカル品質チェックの二層

- `tdd-dev` の品質チェック（対象テスト・関連テスト・lint）は **push 前にローカルで通す**。CI はあくまで最終ゲート（多重防御）であり、ローカル確認を省く口実にしない。
- PR の CI は毎回フルスイート（`scan_ruby` / `scan_js` / `lint` / `test`）を回す。`tdd-dev` が「計画上の区切り（Stage・フェーズ）完了時に全体実行」と定める**全体テストは、PR の CI が自動でカバー**する。ローカルでの全体実行タイミング自体は `tdd-dev` の規則（区切り完了時、未定義なら依頼単位）に従う。

### 11.4 セキュリティチェックの重複と補完

- `tdd-dev` のセキュリティチェックと CI の `scan_ruby`（brakeman / bundler-audit）は重複するが補完関係にある。
  - **ローカル**: `tdd-dev` の該当タイミングで実行（依存追加・更新項目 → bundler-audit＋`bundle check`／認証・認可・Webhook 等の重要変更 → brakeman）。
  - **CI**: PR ごとに `scan_ruby` / `scan_js` が自動実行され、マージゲートになる。
- **秘密情報（認証情報・APIキー・トークン）の差分混入確認は push / PR 前に必ず行う**。本リポジトリは **Public** のため、一度 push すると公開履歴に残り、削除しても取り消せない。`tdd-dev` の「コミット依頼時に混入確認」を push 前チェックとして厳守する。

### 11.5 dependabot PR の扱い

- dependabot の依存更新 PR は、`tdd-dev` の「依存パッケージを追加・更新した項目」に相当する。マージ前にローカルでテスト（可能なら全体）と bundler-audit / `bundle check` を確認してから squash merge する（9章）。

---

## 付録A: RSpec テストジョブの参考定義

`.github/workflows/ci.yml` に追加するジョブ。認証情報は実 `config/database.yml`（`DB_USERNAME=workout_tracker` / `DB_PASSWORD=password`）と `compose.yaml`（`POSTGRES_USER=workout_tracker`）に整合させる。

```yaml
  test:
    runs-on: ubuntu-latest

    services:
      postgres:
        image: postgres:17
        env:
          POSTGRES_USER: workout_tracker
          POSTGRES_PASSWORD: password
        ports:
          - 5432:5432
        options: >-
          --health-cmd "pg_isready -U workout_tracker"
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5

    env:
      RAILS_ENV: test
      DB_HOST: localhost
      DB_USERNAME: workout_tracker
      DB_PASSWORD: password

    steps:
      - name: Checkout code
        uses: actions/checkout@v6

      - name: Set up Ruby
        uses: ruby/setup-ruby@v1
        with:
          bundler-cache: true

      - name: Prepare test database
        run: bin/rails db:test:prepare

      - name: Run tests
        run: bundle exec rspec
```

## 付録B: PR テンプレート（任意）

`.github/pull_request_template.md` に置くと PR 作成時に自動展開される。

```markdown
## 概要
<!-- 何を・なぜ -->

## 変更内容
-

## 確認したこと
- [ ] `bundle exec rspec` が green
- [ ] `bin/rubocop` が green
- [ ] 差分を自分で一読した
```

---

## 変更履歴

- 1.6（2026-08-13）: 8章・付録A の test ジョブを `db:prepare` から `db:test:prepare` に変更（実 `ci.yml` の変更に追従）。`db:prepare` は DB 新規作成時に seed を実行するため、テスト DB へのプリセット混入で spec が落ちる問題が PR #29 で発生した。
- 1.5（2026-08-07）: 7.2 に自動レビューの運用注意を追記。スキップされても success で終わること、再レビューは close → reopen で行うこと、`@claude` メンションは質問用途に限ることを明記。
- 1.4（2026-08-04）: PR 自動レビューの導入に伴い、7.1 に確認工程（6b）、7.2 に運用ルール4項目、9章に dependabot PR が自動レビュー対象外である旨、11章に `docs/pr-review-automation.md` への参照を追加。
- 1.3（2026-07-28）: 付録A の CI テストジョブ例を実環境に整合（`DATABASE_URL: postgres://postgres:postgres` を廃し、`POSTGRES_USER=workout_tracker`／`DB_USERNAME`・`DB_PASSWORD` を実 `database.yml`・`compose.yaml` に合わせた）。実 `ci.yml` の `test` ジョブと一致。
- 1.2（2026-07-28）: 2章のブランチ粒度規則を `plan.md` 起点に変更（「1トピックブランチ ＝ `plan.md` の1項目、または小さな関連項目の集合」）。巨大ブランチ抑止のため。11.1 も同基準に整合。
- 1.1（2026-07-28）: 「11. TDD 開発ワークフロー（tdd-dev）との関係」章を追加（ブランチ粒度＝plan.md項目単位、コミット/squashの関係、品質・セキュリティチェックの二層、dependabot PR）。
- 1.0（2026-07-28）: 初版策定。GitHub Flow / Public / Conventional Commits / squash merge / Ruleset 保護。
