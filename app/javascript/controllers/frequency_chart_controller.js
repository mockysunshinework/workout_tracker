import { Controller } from "@hotwired/stimulus"
// UMD ビルドのためグローバル定義を副作用 import で読み込む（config/importmap.rb 参照）
import "chart.js"
const Chart = window.Chart

// 月間頻度グラフ（SPEC 4.4）: 月ごとの実施日数の棒グラフ。
// データは /charts/training_frequency（6.2）から取得する（直近 6 ヶ月）。
export default class extends Controller {
  static targets = ["canvas"]
  static values = { url: String }

  connect() {
    this.reload()
  }

  disconnect() {
    this.chart?.destroy()
  }

  async reload() {
    const params = new URLSearchParams({ unit: "month", months: "6" })
    const response = await fetch(`${this.urlValue}?${params}`, {
      headers: { Accept: "application/json" }
    })
    if (!response.ok) return

    this.render(await response.json())
  }

  render({ counts }) {
    this.chart?.destroy()
    this.chart = new Chart(this.canvasTarget, {
      type: "bar",
      data: {
        // period_start は ISO 日付（例: 2026-08-01）。月表示なので YYYY-MM に切り詰める
        labels: counts.map((row) => row.period_start.slice(0, 7)),
        datasets: [{ label: "実施日数", data: counts.map((row) => row.days) }]
      },
      options: {
        responsive: true,
        scales: { y: { beginAtZero: true, ticks: { stepSize: 1 } } }
      }
    })
  }
}
