# タスク: ブランチ運用ルールの実運用適用

## 概要

`docs/branching-rules.md`（v1.2）で定めた GitHub Flow ベースのブランチ運用を、`workout_tracker` リポジトリで実際に機能する状態にする。GitHub リポジトリ作成・RSpec を含む CI 構築・main の Ruleset 保護・Squash/自動削除設定・動作確認までを、依存関係順に実施する。

- 本計画は 2026-07-28 にユーザーの指示で改訂済み（下記「問題・計画変更履歴」参照）。
- ローカルのファイル変更は必ずトピックブランチ上で行い、`main` では編集しない（自己ドッグフーディング）。
- コミット・push・PR作成・マージ等の Git 操作は、各操作の直前に内容を報告し、ユーザーの明示的な依頼があった場合のみ実行する。

## 期待される結果

- `origin`（GitHub Public リポジトリ）が存在し、`main` が push 済み
- CI に RSpec の `test` ジョブが加わり、PR で `scan_ruby` / `scan_js` / `lint` / `test` の4チェックが走る
- `main` が Ruleset で保護され、直接 push が拒否され、PR＋CI green＋linear history が強制される
- マージは Squash のみ、マージ後にヘッドブランチが自動削除される
- テスト用 PR で「ブランチ → PR → CI green → squash merge → 自動削除」が一周確認できている
- 実設定と `docs/branching-rules.md` が一致している

## 対象範囲

- ローカル設定ファイルの作成・修正（`.github/workflows/ci.yml`、`.github/pull_request_template.md`、`config/ci.rb`、`docs/branching-rules.md`）
- GitHub リポジトリ作成・push・PR 作成（`gh` / `git`）
- GitHub Web（または `gh api`）での Ruleset・リポジトリ設定
- 一連の動作確認と仕様書照合

## 対象外

- Stage 1 の機能実装（`plan.md` 側の作業）
- CI のセキュリティスキャン内容の改変（既存の brakeman / bundler-audit / importmap audit はそのまま）
- 本番デプロイ・CD の構築

## 制約

- 既存設計とプロジェクト規約（Rails 8 omakase、既存 `bin/` スタブ、`compose.yaml` の DB 設定）を優先する
- タスクに無関係なリファクタリングを行わない
- ファイル変更はトピックブランチ上で行い、`main` では編集しない
- push の前に秘密情報（認証情報・APIキー・トークン）が差分・追跡対象に無いことを必ず確認する
- 破壊的操作（force push、履歴改変、`git reset --hard` を使った main 検証）は行わない
- Git 操作は各操作の直前に報告し、明示依頼時のみ実行する

## 調査結果

### 現在の実装（すべて 2026-07-28 に確認済みの事実）

| 項目 | 確認結果 | 根拠 |
|---|---|---|
| Git 状態 | `main`、コミット1個（`6924cae Initial commit`）、作業ツリーは `docs/`・`plans/` が untracked | `git status` / `git log` |
| リモート `origin` | **未設定** | `git remote -v` が空 |
| GitHub リポジトリ | **未作成**（`mockysunshinework/workout_tracker` は解決不可） | `gh repo view` が `Could not resolve to a Repository` |
| CI 設定 | `.github/workflows/ci.yml` に `scan_ruby`(brakeman/bundler-audit) / `scan_js`(importmap audit) / `lint`(rubocop)。**RSpec の `test` ジョブは無い**。トリガーは `pull_request` と `push: main` | `ci.yml` 実読 |
| 検証ツール導入 | `rspec-rails` / `factory_bot_rails` / `bundler-audit` / `brakeman` / `rubocop-rails-omakase` すべて Gemfile にあり、`Gemfile.lock` 存在。`bin/` に `brakeman` `bundler-audit` `rubocop` `ci` スタブあり | `Gemfile` / `bin/` |
| 正式な実行コマンド | テスト: `bundle exec rspec`、Lint: `bin/rubocop`、Brakeman: `bin/brakeman`、gem監査: `bin/bundler-audit`、JS監査: `bin/importmap audit`、ローカル一括: `bin/ci`（`config/ci.rb`） | `.rspec` / `config/ci.rb` / CI |
| DB 設定 | `config/database.yml` は `DB_HOST`(既定localhost) / `DB_USERNAME`(既定 `workout_tracker`) / `DB_PASSWORD`(既定 `password`)。test DB = `workout_tracker_test`。`DATABASE_URL` があればマージ。`compose.yaml` は postgres:17・`POSTGRES_USER=workout_tracker`・`POSTGRES_PASSWORD=password`・5432 | 両ファイル実読 |
| dependabot | `.github/dependabot.yml` あり（bundler / github-actions weekly、上限10） | 実読 |
| PR テンプレート | **無し**（`.github/pull_request_template.md` 不在） | `ls` |
| `gh` CLI | インストール済み（2.89.0）、`mockysunshinework` で認証済み、スコープ `gist, read:org, repo, workflow`（repo 作成・workflow push・Ruleset API 可能） | `gh --version` / `gh auth status` |
| `config/ci.rb` | Rails 8 の `bin/ci` ローカルランナー。ステップは Setup / Style:Ruby / gem audit / importmap audit / brakeman。**RSpec ステップは無い** | 実読 |
| Ruby / Rails | Ruby 3.3.10 / Rails ~> 8.1.3 | `.ruby-version` / `Gemfile` |

### 既に完了している作業（根拠あり）

- ブランチ運用仕様書 `docs/branching-rules.md`（v1.2）作成済み（ただし **git 未追跡**）
- CI のセキュリティスキャン3ジョブ・dependabot は導入済み
- 検証 gem・`bin/` スタブは導入済み（追加インストール不要）

### 類似実装・既存パターン

- `config/ci.rb` の各ステップは `step "ラベル", "コマンド"` 形式。RSpec 追加は `step "Test: RSpec", "bundle exec rspec"` を既存記法どおり追記する
- 付録A（仕様書）の CI テストジョブ例を、この既存 DB 設定に合わせて調整する

### 未確認事項

- なし（Public 作成・`config/ci.rb` への RSpec 追加はユーザー承認済み 2026-07-28）

### 仮定

- GitHub リポジトリはユーザー個人アカウント（`mockysunshinework`）配下に `workout_tracker` の名前で作成する
- Ruleset は Public リポジトリのため Free プランで利用可能（GitHub の Repository Rulesets）
- CI ランナー（ubuntu-latest）で postgres サービスコンテナを `localhost:5432` として利用できる

## 影響範囲

| 領域 | 影響 | 内容 |
|---|---|---|
| Model・Domain | なし | アプリコードは変更しない |
| Controller・API | なし | 同上 |
| View・Frontend | なし | 同上 |
| Database | なし（設定のみ） | DB スキーマ変更なし。CI で test DB を作る設定のみ |
| Job・Mailer | なし | 同上 |
| 外部サービス | あり | GitHub リポジトリ作成・push・Ruleset 設定（`gh` / Web） |
| テスト | あり | CI・ローカル `bin/ci` に RSpec 実行を追加。ローカルで rspec を実行し検証 |
| ドキュメント | あり | `docs/branching-rules.md` 付録A の DB 設定を実環境に整合。本計画ファイル追加 |

## 変更予定ファイル

| ファイル | 種別 | 変更内容 | 根拠 |
|---|---|---|---|
| `.github/workflows/ci.yml` | 変更 | `test` ジョブ追加（postgres サービス＋`RAILS_ENV=test bin/rails db:prepare`＋`bundle exec rspec`、env を `database.yml` に整合） | 「CI green 必須」を実効化（仕様書8章） |
| `.github/pull_request_template.md` | 新規 | 付録B の PR テンプレート | PR 運用の定着（仕様書7.2・付録B） |
| `config/ci.rb` | 変更 | ローカル `bin/ci` に「Test: RSpec」ステップ追加 | ローカルCIとGitHub CIの整合（ユーザー承認済み） |
| `docs/branching-rules.md` | 変更 | 付録A の DB env を実 `database.yml` に整合、変更履歴追記 | 付録Aの例が実設定と不一致（F3） |
| `plans/PLAN-branching-rules.md` | 新規 | 本計画 | 適用作業の管理 |
| `bin/importmap` / `config/importmap.rb` / `app/javascript/application.js` / `vendor/javascript/.keep` | 新規 | `importmap:install` の生成物 | 既存問題1の解消（scan_js を通す） |
| `app/views/layouts/application.html.erb` | 変更 | `javascript_importmap_tags` 挿入（install が自動追加） | 同上 |

## リスク

| リスク | 可能性 | 影響 | 対応・確認方法 |
|---|---|---|---|
| 付録AのDB例（`postgres:postgres`）のままCI作成し、test が接続失敗 | 高 | 中 | env を `database.yml`（`workout_tracker`/`password`）に整合。失敗時は CI ログの接続エラーを確認 |
| 必須チェック登録前にCI未実行で、チェック名が選択肢に出ない | 中 | 中 | 先にPRでCIを1回走らせてから Ruleset に登録（フェーズ5→6の順序厳守） |
| 秘密情報が公開リポジトリに混入 | 低 | 高 | push 前に `git diff` と追跡対象を確認。第三者に取得・複製された内容は削除しても回収を保証できないため、混入時は該当鍵の**失効・再発行（ローテーション）**を行う |
| 直push拒否テストが実際には ref 更新を伴わず「テストになっていない」 | 中 | 低 | 補足A: テストは main より1コミット先行したトピックブランチから実行する |
| squash マージ後にローカルブランチ削除が拒否される | 低 | 低 | 補足B: squash 後は未マージ判定になるため `git branch -D`（大文字）で削除 |
| Squash 未設定のまま最初のマージを行い merge commit が残る | 低 | 低 | 最初のマージ（フェーズ8）より前にリポジトリ設定（フェーズ7）を完了 |

## ロールバック方針

- ローカルファイル: 変更は topic ブランチ上で行うため、ブランチ削除で破棄可能。マージ済みは `git revert`
- GitHub リポジトリ: 誤作成時は `gh repo delete`（要確認プロンプト）で削除可能
- Ruleset・リポジトリ設定: Web または `gh api` で Disable / 変更で可逆
- DB 変更なし
- 不可逆な点: 一度 push した内容は、第三者に取得・複製されると後から削除しても回収を保証できない。秘密情報を含めないことで回避し、万一混入した場合は該当情報を失効・再発行する

## チェックリスト

> 操作種別の凡例: 【調査】=読み取りのみ / 【ローカル】=ファイル作成・変更 / 【Git/gh】=コマンド実行（各操作の直前に報告し明示依頼時のみ実行）/ 【Web】=GitHub画面で手動設定（`gh api` 代替可） / 【CI待ち】=CIを1回実行しないと次へ進めない / 【要確認】=ユーザー確認・承認が必要

### フェーズ0: 現状調査（今回実施・完了）

- [x] ステップ0.1: 【調査】Git 状態・ブランチ・作業ツリーを確認（`main`/1コミット/`docs/`・`plans/` untracked）
- [x] ステップ0.2: 【調査】リモート `origin` の有無を確認（未設定）
- [x] ステップ0.3: 【調査】GitHub リポジトリの有無を確認（未作成）
- [x] ステップ0.4: 【調査】`.github/workflows/ci.yml` の内容を確認（test ジョブ無し）
- [x] ステップ0.5: 【調査】RSpec/RuboCop/Brakeman/bundler-audit の導入と実行コマンドを確認
- [x] ステップ0.6: 【調査】`config/database.yml` と `compose.yaml` の PostgreSQL 設定を確認
- [x] ステップ0.7: 【調査】`.github/dependabot.yml`・PRテンプレートの有無を確認（dependabotあり/PRテンプレなし）
- [x] ステップ0.8: 【調査】`gh` CLI の導入・認証・スコープを確認（認証済み・repo/workflow あり）
- [x] ステップ0.9: 【調査】`config/ci.rb`（bin/ci）を確認（rspec ステップ無し・`step` 記法）

### フェーズ1: GitHub リポジトリ作成・baseline push・トピックブランチ作成（承認後）

- [x] ステップ1.1: 【要確認】Public リポジトリ作成の最終確認（ユーザー承認済み 2026-07-28）
  - 目的: 不可逆な公開の前に意思確認
  - 完了条件: 作成を実行してよい旨の確認
  - 注意点: 第三者が取得・複製した内容は後から削除しても回収を保証できない
- [x] ステップ1.2: 【要確認/Git】push 前の秘密情報混入確認
  - 対象: 追跡予定ファイル全体
  - 作業: `git status` 確認、`config/master.key` が `.gitignore` 済みか、`credentials.yml.enc` 以外に平文の鍵が無いか確認
  - 実行コマンド: `git check-ignore config/master.key`（無視されていること）
  - 完了条件: 秘密情報が追跡対象に無い
  - 結果（2026-07-28）: `master.key` は ignored、追跡機密は暗号化済み `credentials.yml.enc` のみ、平文鍵なし → OK
- [x] ステップ1.3: 【Git/gh】GitHub リポジトリ作成と baseline（main）push
  - 目的: `origin` を用意し `main` のベースラインを push（`docs/`・`plans/` は次フェーズのトピックブランチPRで取り込む）
  - 前提: ステップ1.1・1.2 完了、カレントブランチが `main`
  - 実行コマンド: `gh repo create workout_tracker --public --source=. --remote=origin --push`
  - 完了条件: `git remote -v` に `origin`、GitHub 上に `main` と `Initial commit` が見え、default branch が `main`
  - 注意点: この push は **Ruleset 設定前**のブートストラップ。以降 `main` へ直接 push しない
  - 結果（2026-07-28）: https://github.com/mockysunshinework/workout_tracker 作成、`main` push 済み、`origin` 追跡設定
- [x] ステップ1.4: 【Git/gh】トピックブランチ作成
  - 作業: `git switch -c ci/branching-setup`
  - 完了条件: `ci/branching-setup` に切替済み（以降のファイル変更はこのブランチ上で行う）
  - 結果（2026-07-28）: `ci/branching-setup` を作成・切替済み

### フェーズ2: ローカル設定ファイルの作成・修正（トピックブランチ上）

- [x] ステップ2.1: 【ローカル】`ci.yml` に RSpec `test` ジョブを追加
  - 目的: PR マージゲートに自動テストを含める
  - 対象: `.github/workflows/ci.yml`
  - 作業: postgres:17 サービス（`POSTGRES_USER=workout_tracker` / `POSTGRES_PASSWORD=password`）を定義、env に `RAILS_ENV=test` `DB_HOST=localhost` `DB_USERNAME=workout_tracker` `DB_PASSWORD=password` を設定、`ruby/setup-ruby`(bundler-cache) → `bin/rails db:prepare` → `bundle exec rspec` を実行する job `test` を追記。**付録Aの `DATABASE_URL: postgres://postgres:postgres` は使わず、実 `database.yml` の認証情報に合わせる**
  - 完了条件: job `test` が追加され YAML が妥当
  - 注意点: ジョブ名 `test` がそのまま必須チェック名になる（フェーズ6で登録）
- [x] ステップ2.2: 【ローカル】PR テンプレートを作成
  - 対象: `.github/pull_request_template.md`（新規、仕様書 付録B）
  - 完了条件: rspec/rubocop/差分確認のチェック項目を含むファイルが存在
- [x] ステップ2.3: 【ローカル】`config/ci.rb` に RSpec ステップを追加
  - 目的: ローカル `bin/ci` と GitHub CI の整合
  - 対象: `config/ci.rb`
  - 作業: 既存記法で `step "Test: RSpec", "bundle exec rspec"` を Setup ステップの後に追加
  - 完了条件: `config/ci.rb` に Test ステップが入る
  - 注意点: `bin/ci` 実行時は test DB が用意済みである必要がある（フェーズ3で準備）
- [x] ステップ2.4: 【ローカル】仕様書 付録A の DB env を実設定に整合
  - 対象: `docs/branching-rules.md`（付録A・変更履歴）
  - 作業: 付録Aの env をステップ2.1と同じ内容へ更新、版を上げ変更履歴に追記
  - 完了条件: 付録Aの例が実 `ci.yml` と一致

### フェーズ3: ローカル CI 検証（push 前）

- [x] ステップ3.1: 【Git/gh】DB コンテナ起動と test DB 準備
  - 実行コマンド: `docker compose up -d db` → `RAILS_ENV=test bin/rails db:prepare`
  - 完了条件: test DB（`workout_tracker_test`）が作成され接続できる
  - 注意点: 5432 が使用中なら停止するかポート調整
- [x] ステップ3.2: 【Git/gh】ローカルで RSpec を実行し green を確認
  - 実行コマンド: `bundle exec rspec`
  - 完了条件: 失敗0（現状最小 spec のため 0 examples でも可。接続できることが要点）
  - 注意点: 接続エラーは env / コンテナ稼働を確認
- [x] ステップ3.3: 【Git/gh】CI 相当の他チェックをローカル実行
  - 実行コマンド: `bin/ci`（または個別に `bin/rubocop` / `bin/brakeman --no-pager` / `bin/bundler-audit` / `bin/importmap audit`）
  - 完了条件: すべて green（警告があれば内容を記録）

### フェーズ4: push と PR 作成

- [x] ステップ4.1: 【要確認/Git】変更をコミット（`89a7d3f`、10ファイル・702行追加）
  - 作業: `ci.yml`・PRテンプレート・`config/ci.rb`・`docs/branching-rules.md`・`plans/PLAN-branching-rules.md` を add。秘密情報が差分に無いことを再確認してコミット（Conventional Commits）
  - 実行コマンド例: `git add -A && git commit -m "ci: add rspec job and branch workflow docs"`
  - 完了条件: コミット済み、`git status` クリーン
- [x] ステップ4.2: 【要確認/Git/gh】push と PR 作成（PR #4 作成、gh auth setup-git で認証設定）
  - 作業: `git push -u origin ci/branching-setup` → `gh pr create --base main --fill`（タイトルは Conventional Commits）
  - 完了条件: PR が作成され URL が得られる

### フェーズ5: CI チェック名の実体化

- [x] ステップ5.1: 【CI待ち】PR 上で CI を1回走らせ、4チェックを green にする（PR #4 で scan_ruby/scan_js/lint/test すべて pass）
  - 目的: `scan_ruby` / `scan_js` / `lint` / `test` を GitHub 上に実体化（Ruleset 登録の前提）
  - 確認コマンド: `gh pr checks <PR番号>` / `gh run watch`
  - 完了条件: 4チェックが PR 上に出現し、すべて green
  - 注意点: `test` が赤なら CI ログで DB 接続・`db:prepare` を確認（付録A流用の env ミスが典型）

### フェーズ6: GitHub Ruleset への必須チェック登録

- [x] ステップ6.1: 【Web】main の Ruleset を作成・有効化（`protect main` active、必須チェック4つ・PR必須・linear history・force push/削除禁止を gh api で検証済み）
  - 対象: Settings → Rules → Rulesets（新規 branch ruleset、対象 `main`）
  - 設定: Restrict deletions / Block force pushes / Require a pull request before merging（承認0）/ Require status checks（`scan_ruby`・`scan_js`・`lint`・`test`、Require branches up to date 有効）/ Require linear history
  - 前提: フェーズ5完了（チェック名が選択肢に出る）
  - 完了条件: Ruleset が Enabled
  - 手動操作: **Web 画面での設定（ユーザー実施）**。代替 `gh api -X POST repos/{owner}/{repo}/rulesets`
  - 注意点: 実行実績のあるチェック名のみ選択可。出ない場合はフェーズ5未完

### フェーズ7: リポジトリ設定（Squash・自動削除）

- [x] ステップ7.1: 【Web】マージ方式を Squash のみに制限（squash=true, merge/rebase=false を検証済み）
  - 実行コマンド（代替）: `gh repo edit --enable-merge-commit=false --enable-rebase-merge=false --enable-squash-merge=true`
  - 完了条件: Squash のみ有効
- [x] ステップ7.2: 【Web】ヘッドブランチ自動削除を有効化（delete_branch_on_merge=true を検証済み）
  - 実行コマンド（代替）: `gh repo edit --delete-branch-on-merge=true`
  - 確認コマンド: `gh api repos/{owner}/{repo} --jq '.delete_branch_on_merge'` が `true`
  - 完了条件: 設定反映
  - 注意点: フェーズ8（最初のマージ）より前に完了させる

### フェーズ8: テスト用 PR による一連の動作確認

- [x] ステップ8.1: 【要確認/Git/gh】main への直接 push が拒否されることを確認（安全手順・補足A）
  - 前提: フェーズ6の Ruleset 有効。ブランチが **main より1コミット以上先行**していること
  - 作業: 使い捨てブランチ上から `git push origin HEAD:main` を実行し、拒否されることを確認（ローカル `main` は一切変更しない）
  - 完了条件: protection によりリジェクトされる
  - 結果（2026-07-29）: 初回は反映遅延で通過（問題2）。再検証で `chore/protection-retest` から直push → `GH013: ... Changes must be made through a pull request / 4 of 4 required status checks are expected` で**拒否**を確認 → 保護有効
- [x] ステップ8.2: 【要確認/Git/gh】自動削除を確認（補足B）
  - 結果（2026-07-29）: PR #4 は直push検知により MERGED 扱いとなり、`delete_branch_on_merge` によりリモート `ci/branching-setup` が**自動削除**されたことを `git ls-remote` で確認済み。squash-merge ボタン経由の一連は 8.3 の最終PRで検証する
- [ ] ステップ8.3: 【Git/gh】最終検証PRで squash-merge ボタン経由の一連を確認（#6 該当・plan更新の反映を兼ねる）
  - 実施理由: PR #4 は直push検知で merged 扱いになり、squash-merge ボタン → main に squash 1コミット の経路が未実演。かつ plan/docs の以降の更新は直push不可のため PR で反映する必要がある
  - 作業: `docs/finalize-branching-plan` で plan 更新をコミット → PR → CI green → `gh pr merge --squash` → `main` に squash 1コミット、リモートブランチ自動削除を確認
  - 完了条件: PR経由の squash マージが成功し、main が linear なまま1コミット増え、ヘッドブランチが自動削除される

### フェーズ9: 仕様書との最終照合

- [ ] ステップ9.1: 【調査】`docs/branching-rules.md` と実設定を照合（2章/5章/6章/8章/11章）
  - 完了条件: 各規則と実設定・実CIが一致
- [ ] ステップ9.2: 【ローカル】不一致があれば仕様書または設定を修正し変更履歴に記録
  - 完了条件: 乖離ゼロ、または残差が明記
- [ ] ステップ9.3: 【要確認】ユーザーへ最終報告と確認

## 完了条件

- [ ] `origin`（Public）が存在し `main` が push 済み
- [ ] CI に `test`（RSpec）ジョブがあり PR で green になる
- [ ] `main` の Ruleset（直push禁止・PR必須・status checks 4つ・linear history・force-push/削除禁止）が有効
- [ ] Squash のみ許可・ヘッドブランチ自動削除が有効
- [ ] テスト用 PR で一連のフローが確認済み
- [ ] `docs/branching-rules.md` と実設定が一致
- [ ] 未確認・未解決事項が記録されている

## 結果・発見事項

- 2026-07-28: **F1** GitHub リポジトリ・`origin` は未作成。適用にはリポジトリ作成＋baseline push が必要。
- 2026-07-28: **F2** `ci.yml` に RSpec `test` ジョブが無い。「CI green 必須」の実効化に追加必須。
- 2026-07-28: **F3** 仕様書 付録A の CI 例が `DATABASE_URL: postgres://postgres:postgres` で、実 `database.yml`（`workout_tracker`/`password`）と不一致。実装時に整合が必要。
- 2026-07-28: **F4** `config/ci.rb`（ローカル `bin/ci`）にも RSpec ステップが無い。整合のため追加する（ユーザー承認済み）。
- 2026-07-28: **F5** PR テンプレート未作成（付録B を作成予定）。
- 2026-07-28: **F6** `docs/branching-rules.md`・`plans/` は git 未追跡。初回のブートストラップ PR で取り込む。
- 2026-07-28: **F7** `gh` は認証済みでスコープ `repo`/`workflow` を保持。リポジトリ作成・workflow push・Ruleset API 操作が可能。
- 2026-07-28: **F8** dependabot・検証 gem・`bin/` スタブは導入済み。追加インストール不要。

## 問題・計画変更履歴

### 問題2（2026-07-29・直push拒否テストが通過）

- 該当ステップ: フェーズ8.1（直push拒否テスト）
- 問題: Ruleset 有効・bypass無し・`current_user_can_bypass=never` にもかかわらず、`git push origin HEAD:main`（FF）が拒否されず `origin/main` が `89a7d3f` に更新された。GitHub は PR #4 を MERGED 扱いにした
- 確認した事実: 評価API `rules/branches/main` は5ルールとも適用中と応答。設定自体は正しい。リモートの `ci/branching-setup` は自動削除された（`delete_branch_on_merge` は機能）
- 原因（推定）: Ruleset 作成直後の enforcement 反映遅延。設定APIは即 active を返すが、push 強制層の有効化にラグがあり、その隙に FF push が通った可能性が高い（未確定）
- 影響: `main` の内容は正しい（`89a7d3f` はレビュー済み・CI green）。ただし直pushで入ったこと、保護の実効性が未確認
- 対応（予定）: (1) ローカル `main` を `origin/main` に同期 (2) ローカル `ci/branching-setup` 削除 (3) **保護の再検証**（新規使い捨てコミットで直push拒否を再試行し、今度は拒否されることを確認）
- 対応結果（2026-07-29）: ①ローカル main を 89a7d3f に同期 ②`ci/branching-setup` 削除 ③再検証で直push が `GH013` により拒否されることを確認。**原因は反映遅延と確定、現在は保護有効**。教訓: Ruleset 作成直後は enforcement 反映に数秒のラグがあり得るため、直後の検証は時間を置くか再試行する
- ユーザー確認: 済

### 問題1（2026-07-28・既存問題の発見）

- 該当ステップ: フェーズ3（ローカル検証）、フェーズ6（必須チェック登録）
- 問題: `importmap-rails` gem は導入済みだが未初期化（`bin/importmap`・`config/importmap.rb`・`app/javascript/` が無い）。`bin/importmap audit` が実行不能（ローカル exit 127）
- 原因: Initial commit 時に `importmap:install` 未実行。JS層が未セットアップ
- 影響: 既存の `scan_js` ジョブおよび `config/ci.rb` の importmap ステップが CI/ローカルで失敗する。`scan_js` を必須チェックに登録するとPRがマージ不能になる
- 対応案: (A) `bin/rails importmap:install` で初期化 / (B) `scan_js` ジョブと `config/ci.rb` の importmap ステップを削除し必須チェックを scan_ruby/lint/test の3つに / (C) 保留し別タスク化
- 今回の変更との関係: **無関係の既存問題**（RSpec/RuboCop/Brakeman/bundler-audit はすべて green）
- 対応（2026-07-28）: ユーザー承認のもと方針A採用。`bin/rails importmap:install` を実行し `bin/importmap`・`config/importmap.rb`・`app/javascript/application.js`・`vendor/javascript/`・layout の `javascript_importmap_tags` を生成。`bin/importmap audit` = No vulnerable packages、RuboCop offense なし、`Gemfile.lock` 変化なし。RSpec/Brakeman/bundler-audit も green
- ユーザー確認: 済（方針A承認）

### 改訂1（2026-07-28・ユーザー指示）

- 該当ステップ: フェーズ構成全体、直push検証、自動削除検証、DB準備、セキュリティ表現、任意ステップ
- 変更内容:
  1. GitHub リポジトリ作成・baseline push・トピックブランチ作成を、ローカル設定ファイル変更より**前**へ移動。ファイル変更はトピックブランチ上でのみ行う
  2. 直push拒否の確認を、`main` への空コミット＋`git reset --hard` 方式から、トピックブランチ上での `git push origin HEAD:main` 方式へ変更（補足A: main より先行したブランチで実行）
  3. 自動削除の初回検証で `gh pr merge --delete-branch` を使わず `--squash` のみとし、GitHub 側の自動削除を確認。ローカルは後から `git branch -D`（補足B）
  4. test DB 準備コマンドを `RAILS_ENV=test bin/rails db:prepare` と明記
  5. 「Public 履歴は不可逆」を「第三者に取得・複製された内容は削除しても回収を保証できない／秘密情報は失効・再発行が必要」に修正
  6. 2回目の使い捨て PR を、ブートストラップ PR で確認できなかった項目がある場合のみの任意ステップに変更
- ユーザー確認: 済（本改訂の指示元）

## 実行した検証

| 検証内容 | コマンド・方法 | 結果 |
|---|---|---|
| Git/リモート/リポジトリ状態 | `git status` / `git remote -v` / `gh repo view` | 実施（main単一・origin無し・GitHub未作成） |
| CI/ツール/DB/gh 調査 | `cat ci.yml` / `Gemfile` / `database.yml` / `config/ci.rb` / `gh auth status` | 実施 |
| ローカル RSpec 実行 | `bundle exec rspec` | 未実施（実装フェーズで実行予定） |
| CI 実行 | GitHub Actions | 未実施（リポジトリ未作成のため） |

## 次のステップ

- 調査・計画作成・計画改訂（改訂1）は完了
- 実装は未着手（ソースコード・CI・Git設定・GitHub設定の変更、ブランチ作成、コミット、push、PR、マージはいずれも未実施）
- 承認済みのため、フェーズ1から着手する。ただし Git 操作（repo作成/push/コミット/PR/マージ）は各操作の直前に報告し、明示依頼時のみ実行する
