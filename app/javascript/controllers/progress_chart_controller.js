import { Controller } from "@hotwired/stimulus"
// UMD ビルドのためグローバル定義を副作用 import で読み込む（config/importmap.rb 参照）
import "chart.js"
const Chart = window.Chart

// 種目別推移グラフ（SPEC 4.4）: 折れ線 2 系列（最大重量・推定 1RM）。
// データは /charts/exercise_progress（6.2）から取得する。
export default class extends Controller {
  static targets = ["canvas", "exerciseSelect", "monthsSelect"]
  static values = { url: String }

  connect() {
    this.reload()
  }

  disconnect() {
    this.chart?.destroy()
  }

  async reload() { // await を使う関数にはasync をつける。
    const exerciseId = this.exerciseSelectTarget.value
    if (!exerciseId) return

    const params = new URLSearchParams({
      exercise_id: exerciseId,
      months: this.monthsSelectTarget.value
    })
    const response = await fetch(`${this.urlValue}?${params}`, {
      headers: { Accept: "application/json" }
    })
    if (!response.ok) return

    this.render(await response.json())
  }

  render({ series }) {
    this.chart?.destroy() //描画のたびに destroy() してから作り直すのは Chart.js の作法（同じ canvas に二重に作るとエラーになるため）
    this.chart = new Chart(this.canvasTarget, {
      type: "line", //折れ線グラフ
      data: {
        labels: series.map((row) => row.date),
        datasets: [ // 2本の線
          { label: "最大重量(kg)", data: series.map((row) => row.max_weight) },
          { label: "推定1RM(kg)", data: series.map((row) => row.estimated_one_rm) }
        ]
      },
      options: { responsive: true } //レスポンシブデザインにする（グラフのサイズを自動調整）
    })
  }
}
