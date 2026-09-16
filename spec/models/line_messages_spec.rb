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

  it "welcome / welcome_back は input_guide を含む" do
    expect(described_class.welcome).to include(described_class.input_guide)
    expect(described_class.welcome_back).to include(described_class.input_guide)
  end
end
