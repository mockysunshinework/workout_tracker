# LINE Login のコールバック URL に使ってよいホスト（8.10・CVE-2026-63183 / GHSA-m27g-v28p-f9fx）。
#
# redirect_uri はリクエストのホストから組み立てている（config/initializers/devise.rb の setup フック）。
# そのホストは Host / X-Forwarded-Host ヘッダー由来で偽装できるため、許可したホスト以外からの
# ログイン開始とコールバックを OmniAuth に拒否させる（失敗時は Devise の failure → ログイン画面）。
# omniauth 2.2.0 の検証は allowed_hosts を設定したときだけ働く。nil のままだと警告を出すだけで素通しになる。
#
# 許可するホストは環境変数 APP_ALLOWED_HOSTS にカンマ区切りで渡す（例: "app.example.jp,abc.ngrok-free.app"）。
# 比較対象は request.host（ホスト名だけ）。URL のまま書かれても（"https://abc.ngrok-free.app" や
# "localhost:3000"）一致するよう、スキーム・ポート・パスは取り除いてホスト名だけを使う。
# IPv6 リテラルは request.host と同じ角括弧付きの形（"[::1]"）で残す。大文字小文字は OmniAuth が無視して比較する。
#   - production: APP_ALLOWED_HOSTS のホストだけ。未設定なら空配列＝どのホストも許可しない
#     （設定漏れを「検証なし」に倒さない。ログインできなくなるので設定漏れにすぐ気付ける）
#   - development: localhost / 127.0.0.1 を既定で許可。ngrok 等のトンネルのホストは APP_ALLOWED_HOSTS で足す
#   - test: 上に加えて request spec の既定ホスト www.example.com
host_pattern = %r{\A(?:[a-z][a-z0-9+.-]*://)?(\[[^\]]+\]|[^:/]+)}i
allowed_hosts = ENV.fetch("APP_ALLOWED_HOSTS", "").split(",").filter_map { |entry| entry.strip[host_pattern, 1] }
allowed_hosts += %w[localhost 127.0.0.1] if Rails.env.local?
allowed_hosts << "www.example.com" if Rails.env.test?

OmniAuth.config.allowed_hosts = allowed_hosts
