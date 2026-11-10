require "rails_helper"

# 9.2 入力案内を短縮記法（SPEC 4.2.2・版 3.2）に差し替える。挨拶・ヘルプ・失敗返信で共用される文言
RSpec.describe LineMessages do
  describe ".input_guide" do
    it "短縮記法の例（種目名 重量/回数/セット数・自重・複数グループ）を含み、旧記法の例を含まない" do
      guide = described_class.input_guide

      expect(guide).to include("ベンチプレス60/5/3")
      expect(guide).to include("懸垂/10/3")
      expect(guide).to include("ベンチプレス60/5 65/5")
      expect(guide).not_to include("60kg 10回")
    end

    # 例はプリセットの正式名称で書く。9.3 の完全一致照合で例をそのまま送っても保存され、
    # 略称（エイリアス・SPEC 10 章 #17 で未確定）が使えると約束しない
    it "種目名の例は略称ではなく正式名称を使う" do
      expect(described_class.input_guide).not_to match(/ベンチ\d/)
    end
  end

  # 9.4 保存内容のエコーバック（SPEC 4.2.3）。グループごとに重量×回数×セット数を個別に列挙し、
  # 合算や省略で打ち間違いが見えなくならないようにする（plan 9.1・2026-09-16 決定）
  describe ".recorded" do
    def group(weight_kg, reps, sets)
      RecordMessageParser::Group.new(weight_kg: weight_kg && BigDecimal(weight_kg.to_s), reps: reps, sets: sets)
    end

    let(:saved) do
      RecordMessageHandler::Saved.new(
        performed_on: Date.new(2026, 9, 18),
        entries: [
          RecordMessageHandler::SavedEntry.new(exercise_name: "ベンチプレス", groups: [ group(60, 5, 2), group(62.5, 5, 1) ], daily_set_count: 4),
          RecordMessageHandler::SavedEntry.new(exercise_name: "懸垂", groups: [ group(nil, 10, 3) ], daily_set_count: 3)
        ],
        total_set_count: 7
      )
    end

    it "日付・種目ごとのグループ列挙・種目の当日セット数・当日合計を含む" do
      text = described_class.recorded(saved)

      expect(text).to include("9/18")
      expect(text).to include("ベンチプレス 60kg×5回×2セット / 62.5kg×5回×1セット（本日 計4セット）")
      expect(text).to include("懸垂 自重×10回×3セット（本日 計3セット）")
      expect(text).to include("本日合計 7セット")
    end

    it "重量は末尾の .0 を付けずに表示する" do
      expect(described_class.recorded(saved)).not_to include("60.0")
    end
  end

  # 9.5 エラー応答（SPEC 4.2.3 / 4.2.1）
  describe ".parse_failed" do
    it "失敗した行と理由、全行未保存であること、入力例（input_guide）を含む" do
      result = RecordMessageParser.call("ベンチプレス60/5\nベンチプレス60/\nベンチプレス1000/5")
      text = described_class.parse_failed(result)

      expect(text).to include("保存していません")
      expect(text).to include("2行目「ベンチプレス60/」")
      expect(text).to include("3行目「ベンチプレス1000/5」")
      expect(text).to match(/3行目.*重量/)
      expect(text).not_to include("1行目")
      expect(text).to include(described_class.input_guide)
    end

    it "メッセージ全体の失敗（行数超過）は行番号なしで理由を示す" do
      result = RecordMessageParser.call(Array.new(21) { |i| "種目#{i} 60/5" }.join("\n"))
      text = described_class.parse_failed(result)

      expect(text).to include("20 行")
      expect(text).not_to include("行目")
    end
  end

  describe ".unrecognized" do
    it "記録として読み取れなかったことと入力案内を返す" do
      text = described_class.unrecognized

      expect(text).to include("読み取れませんでした")
      expect(text).to include(described_class.input_guide)
    end
  end

  describe ".invalid" do
    it "保存できなかった理由と入力案内を返す" do
      text = described_class.invalid([ "ベンチプレス: 重量を入力してください" ])

      expect(text).to include("保存していません")
      expect(text).to include("ベンチプレス: 重量を入力してください")
      expect(text).to include(described_class.input_guide)
    end
  end

  it "welcome / welcome_back は input_guide を含む" do
    expect(described_class.welcome).to include(described_class.input_guide)
    expect(described_class.welcome_back).to include(described_class.input_guide)
  end
end
