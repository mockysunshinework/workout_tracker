# Spike 記録: LINE Login を omniauth_openid_connect で通す（plan.md 8.4）

- 実施日: 2026-09-04
- 目的: 仕様書 版 3.0 で確定した「Web 認証の LINE Login 一本化」に向け、候補 gem `omniauth_openid_connect` が LINE の OpenID Connect 実装と噛み合うかを、本実装（8.7）の前に開発環境で確認する
- 結果: **通った。** LINE 固有の設定 3 点（HS256 明示・フォーム本文でのクライアント認証・PKCE）が必要
- spike のコードは記録後に削除済み。リポジトリに残したのは Gemfile / Gemfile.lock の変更のみ

---

## 1. 前提

- 8.3 で LINE Login チャネルを Messaging API チャネルと**同一プロバイダー**に作成済み。コールバック URL に `http://localhost:3000/users/auth/line/callback` を登録済み（http の localhost で登録可能だった）
- 資格情報は Rails credentials の `line_login.channel_id` / `line_login.channel_secret`
- 開発サーバーは `bin/rails server -p 3000`

## 2. 事前調査で分かっていたこと

| 事項 | 内容 | 根拠 |
|---|---|---|
| discovery 文書 | `https://access.line.me/.well-known/openid-configuration`。`id_token_signing_alg_values_supported` は **ES256 のみ**、`code_challenge_methods_supported` は S256、`token_endpoint` は `https://api.line.me/oauth2/v2.1/token` | 実際に取得 |
| ID トークンの署名 | **Web ログインでは HS256（チャネルシークレット署名）**。ネイティブ／LIFF では ES256。discovery の広告と食い違う | LINE 公式「ID トークンを検証する」 |
| トークンエンドポイントの認証 | `client_id` / `client_secret` を**フォーム本文**で送る（HTTP Basic ではない） | LINE Login v2.1 API リファレンス |
| strategy の鍵選択 | `decode_id_token` がトークンの `alg` を見て、HS 系なら `client_options.secret`、それ以外なら discovery の JWKS を使う。`client_signing_alg` を指定すると alg 不一致を拒否する | omniauth_openid_connect の `lib/omniauth/strategies/openid_connect.rb` |
| クライアント認証方式 | rack-oauth2 の `client_auth_method` は既定 `:basic`。`:basic` `:jwt_bearer` `:mtls` 等に該当しない値（例 `:other`）で `client_id` / `client_secret` を本文に入れる | rack-oauth2 の `lib/rack/oauth2/client.rb` |

## 3. 追加した gem（ユーザー承認済み）

```ruby
gem "omniauth_openid_connect", "~> 0.8"          # 0.8.0
gem "omniauth-rails_csrf_protection", "~> 2.0"  # 2.0.1
```

- OmniAuth 2 系はリクエストフェーズの GET を拒否するため、ログインボタンは POST。その CSRF 保護に後者が必要
- 連れてくる依存: openid_connect 2.5.0、rack-oauth2、json-jwt、swd、webfinger、validate_url、attr_required、faraday 系、hashie、rack-protection など約 20 gem
- 不採用にした案: `omniauth-oauth2` ＋ 自前 LINE strategy（ID トークン検証を自前で書く保守対象が増える）、`omniauth-line`（2021 年で更新停止）

## 4. spike の構成（すべて削除済み）

### 4.1 初期化子 `config/initializers/omniauth_spike.rb`

Devise を通さず OmniAuth ミドルウェアを直接積んだ。本実装では Devise の `config.omniauth` に同じオプションを渡す。

```ruby
# OmniAuth に LINE という OpenID Connect 認証プロバイダを登録し、POST /users/auth/line を「LINEログイン開始リクエスト」として処理できるようにしている。
if Rails.env.development?
  OmniAuth.config.path_prefix = "/users/auth"   # 登録済みコールバック URL に合わせる（Devise は既定でこの値）
  OmniAuth.config.allowed_request_methods = [ :post ]

  Rails.application.config.middleware.use OmniAuth::Builder do
    provider :openid_connect,
             name: :line,
             issuer: "https://access.line.me",
             discovery: true,
             scope: [ :openid, :profile ],
             response_type: :code,
             pkce: true,
             client_signing_alg: :HS256,   # LINE 固有 (1)
             client_auth_method: :other,   # LINE 固有 (2)
             client_options: {
               identifier: Rails.application.credentials.dig(:line_login, :channel_id),
               secret: Rails.application.credentials.dig(:line_login, :channel_secret),
               redirect_uri: "http://localhost:3000/users/auth/line/callback"
             }
  end
end
```

### 4.2 コントローラ `app/controllers/spike/line_login_controller.rb`

`authenticate_user!` を外し、`index` で POST ボタンを 1 つ描画、`callback` で `request.env["omniauth.auth"]` の内容を平文で返す。トークンや秘密の値は**出力せず presence のみ**。ID トークンの `alg` はヘッダ部を Base64 デコードして読んだ。

```ruby
module Spike
  class LineLoginController < ApplicationController
    skip_before_action :authenticate_user!

    def index
      render html: helpers.button_to("LINE でログイン（spike）", "/users/auth/line", method: :post)
    end

    def callback
      auth = request.env["omniauth.auth"]
      id_token = auth.dig("credentials", "id_token")
      alg = id_token && JSON.parse(Base64.urlsafe_decode64(id_token.split(".").first))["alg"]
      render plain: [
        "provider: #{auth['provider']}",
        "uid (sub): #{auth['uid']}",
        "info.name: #{auth.dig('info', 'name')}",
        "info.image present: #{auth.dig('info', 'image').present?}",
        "id_token present: #{id_token.present?} / alg: #{alg}",
        "access_token present: #{auth.dig('credentials', 'token').present?}",
        "raw_info keys: #{auth.dig('extra', 'raw_info')&.to_h&.keys&.inspect}"
      ].join("\n")
    end
  end
end
```

### 4.3 ルート（`config/routes.rb`・開発限定）

```ruby
if Rails.env.development?
  get "spike/line_login", to: "spike/line_login#index"
  get "users/auth/line/callback", to: "spike/line_login#callback"
end
```

`/users/auth/line`（リクエストフェーズ）はミドルウェアが処理するためルート不要。コールバックはミドルウェアが検証を終えたあとアプリに渡すので、アプリ側のルートが必要。

## 5. 手順

1. Gemfile に gem を追加し `bundle install`
2. 上記 3 ファイルを作成し、`bin/rails runner` で起動とルートを確認
3. `bin/rails server -p 3000` をバックグラウンド起動。`/spike/line_login` が 200 を返すことを curl で確認
4. ブラウザで `http://localhost:3000/spike/line_login` を開き、ボタンを押す → LINE のログイン画面（QR またはメール＋パスワード）→ プロフィール権限を許可
5. コールバック画面の出力を確認
6. サーバー停止、spike ファイル削除、ルート除去。`bundle check` / `bundler-audit check --update` / RSpec 全件 / RuboCop を実行

## 6. 結果

コールバック画面の出力（個人を特定する値は伏せた）:

```
provider: line
uid (sub): U（33 文字の英数字。Messaging API の userId と同じ形式）
info.name: （LINE の表示名）
info.image present: true
id_token present: true / alg: HS256
access_token present: true
raw_info keys: ["sub", "name", "picture", "iss", "aud", "exp", "iat", "nonce", "amr"]
```

読み取れること:

- discovery（issuer 指定）でエンドポイント解決ができた
- ID トークンは実際に **HS256**。`client_signing_alg: :HS256` ＋ `discovery: true` の組み合わせで署名検証が通る（strategy が alg を見てシークレット検証に分岐）
- `client_auth_method: :other` でトークン交換が成功（Basic だと LINE 側で失敗する想定。今回は最初から `:other` で通したため Basic の失敗は未実測）
- PKCE（S256）が通る
- `nonce` がクレームに往復している（strategy がセッション保存値と照合）
- 表示名と画像は ID トークンのクレーム（`name` / `picture`）から取れる。userinfo エンドポイントを別途叩く必要はない
- `amr` は認証手段（例: `pwd` / `lineqr` 等）。本アプリでは使わない

品質・セキュリティチェック: RSpec 239 examples 0 failures、RuboCop 指摘なし、`bundle check` OK、`bundler-audit` 脆弱性なし。

## 7. 未検証・注意

- **Bot 側 userId との一致は未検証**。Webhook で userId を受け取れる 8.9 以降、または 12.1 の実機確認で照合する。同一プロバイダーであることは 8.3 で確認済みで、公式ドキュメント上は一致するはず
- `redirect_uri` は環境ごとに変わる。本実装では Devise がコールバック URL を組み立てるため固定値は不要だが、LINE Developers コンソールへの**登録は環境ごとに必要**（本番 URL はホスティング確定後）
- Chrome が `/.well-known/appspecific/com.chrome.devtools.json` を取りに来て RoutingError がログに出るが、DevTools の探索であり無関係

## 8. 8.7（本実装）への持ち込み

```ruby
# config/initializers/devise.rb
config.omniauth :openid_connect,
                name: :line,
                issuer: "https://access.line.me",
                discovery: true,
                scope: [ :openid, :profile ],
                response_type: :code,
                pkce: true,
                client_signing_alg: :HS256,
                client_auth_method: :other,
                client_options: {
                  identifier: Rails.application.credentials.dig(:line_login, :channel_id),
                  secret: Rails.application.credentials.dig(:line_login, :channel_secret)
                }
```

- User は `devise :omniauthable, omniauth_providers: [:line]`（8.6）
- ルートは `devise_for :users, skip: [:registrations, :passwords], controllers: { omniauth_callbacks: "users/omniauth_callbacks" }`
- コールバックで `request.env["omniauth.auth"]` の `uid` を `line_user_id`、`info.name` を表示名として find_or_create（仕様書 4.1.1）
- テストは `OmniAuth.config.test_mode = true` と `OmniAuth.config.mock_auth[:line]` で LINE をモックする（仕様書 9 章）

## 参照

- plan.md 8.3 / 8.4、仕様書 4.1.2 / 10 章 #16（版 3.1）
- LINE 公式: [ID トークンを検証する](https://developers.line.biz/ja/docs/line-login/verify-id-token/)、[LINE Login v2.1 API リファレンス](https://developers.line.biz/ja/reference/line-login/)、[ユーザー ID を取得する](https://developers.line.biz/ja/docs/messaging-api/getting-user-ids/)
- [omniauth_openid_connect](https://github.com/omniauth/omniauth_openid_connect)、[rack-oauth2](https://github.com/nov/rack-oauth2)
