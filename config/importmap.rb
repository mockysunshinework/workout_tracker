# Pin npm packages by running ./bin/importmap

pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin_all_from "app/javascript/controllers", under: "controllers"
# UMD 単一ファイル（4.5.1・自己完結）。jspm の ESM 版は相対パスのチャンクを import しており
# `bin/importmap pin` では取り込めないため、UMD を採用（グローバル window.Chart を定義する）
pin "chart.js", to: "chart.umd.js"
