require "rails_helper"

# 9.2 記録メッセージの短縮記法パーサー（SPEC 4.2.2・版 3.2）。
# ケース表は plan.md 9.1（受理 A1〜A17 / 拒否 R1〜R14）。example 名の A/R 番号はそれに対応する。
RSpec.describe RecordMessageParser, type: :model do
  def parse(text)
    described_class.call(text)
  end

  # 1 行・1 種目の結果を [種目名, [[重量, 回数, セット数], ...]] に畳む（可読性のため）
  def entry_of(text)
    result = parse(text)
    expect(result).to be_success, -> { "expected success but got errors: #{result.errors.inspect}" }
    expect(result.entries.size).to eq 1
    entry = result.entries.first
    [ entry.exercise_name, entry.groups.map { |g| [ g.weight_kg, g.reps, g.sets ] } ]
  end

  def reasons_of(text)
    result = parse(text)
    expect(result).not_to be_success
    result.errors.map(&:reason)
  end

  describe "受理（A）" do
    it "A1 セット数省略は 1 セット" do
      expect(entry_of("ベンチ60/5")).to eq [ "ベンチ", [ [ 60, 5, 1 ] ] ]
    end

    it "A2 重量/回数/セット数" do
      expect(entry_of("ベンチ60/5/3")).to eq [ "ベンチ", [ [ 60, 5, 3 ] ] ]
    end

    it "A3 複数グループは各 1 セット、順序を保つ" do
      expect(entry_of("ベンチ60/5 65/5 70/3")).to eq [ "ベンチ", [ [ 60, 5, 1 ], [ 65, 5, 1 ], [ 70, 3, 1 ] ] ]
    end

    it "A4 グループごとのセット数" do
      expect(entry_of("ベンチ60/5/2 60/7")).to eq [ "ベンチ", [ [ 60, 5, 2 ], [ 60, 7, 1 ] ] ]
    end

    it "A5 自重は重量を空にする（NULL）。スペースの有無・複数グループも可" do
      expect(entry_of("懸垂/10/3")).to eq [ "懸垂", [ [ nil, 10, 3 ] ] ]
      expect(entry_of("懸垂 /10/3")).to eq [ "懸垂", [ [ nil, 10, 3 ] ] ]
      expect(entry_of("懸垂/10 /12")).to eq [ "懸垂", [ [ nil, 10, 1 ], [ nil, 12, 1 ] ] ]
    end

    it "A6 単位は対応する位置なら任意" do
      expected = [ "ベンチ", [ [ 60, 5, 3 ] ] ]
      expect(entry_of("ベンチ60kg/5/3")).to eq expected
      expect(entry_of("ベンチ60kg/5回/3セット")).to eq expected
      expect(entry_of("ベンチ 60kg/5回/3セット")).to eq expected
    end

    it "A7 単位の別名（大小文字不問）" do
      %w[60KG 60㎏ 60キロ 60キログラム 60Kg].each do |w|
        expect(entry_of("ベンチ#{w}/5")).to eq([ "ベンチ", [ [ 60, 5, 1 ] ] ]), w
      end
      %w[5rep 5reps 5レップ 5REP 5Reps].each do |r|
        expect(entry_of("ベンチ60/#{r}")).to eq([ "ベンチ", [ [ 60, 5, 1 ] ] ]), r
      end
      %w[3set 3sets 3SET 3Sets 3セット].each do |s|
        expect(entry_of("ベンチ60/5/#{s}")).to eq([ "ベンチ", [ [ 60, 5, 3 ] ] ]), s
      end
    end

    it "A8 種目名と数値の間のスペースは任意" do
      expect(entry_of("ベンチ 60/5/3")).to eq [ "ベンチ", [ [ 60, 5, 3 ] ] ]
    end

    it "A9 種目名の内部スペースは 1 つに畳んで保持する" do
      expect(entry_of("ブルガリアン スクワット 20/10")).to eq [ "ブルガリアン スクワット", [ [ 20, 10, 1 ] ] ]
      expect(entry_of("ブルガリアン   スクワット20/10")).to eq [ "ブルガリアン スクワット", [ [ 20, 10, 1 ] ] ]
    end

    it "A10 数字を含む種目名（数値の直前が数字でない位置で区切る）" do
      expect(entry_of("45度レッグプレス100/12")).to eq [ "45度レッグプレス", [ [ 100, 12, 1 ] ] ]
      expect(entry_of("45度レッグプレス 100/12")).to eq [ "45度レッグプレス", [ [ 100, 12, 1 ] ] ]
    end

    it "A11 小数 1 桁の重量" do
      expect(entry_of("ベンチ62.5/5")).to eq [ "ベンチ", [ [ 62.5, 5, 1 ] ] ]
      expect(entry_of("ベンチ62.5kg/5")).to eq [ "ベンチ", [ [ 62.5, 5, 1 ] ] ]
      expect(parse("ベンチ62.5/5").entries.first.groups.first.weight_kg).to be_a(BigDecimal)
    end

    it "A12 全角数字・全角スラッシュ・全角スペースを NFKC で吸収する" do
      expect(entry_of("ベンチ６０／５／３")).to eq [ "ベンチ", [ [ 60, 5, 3 ] ] ]
      expect(entry_of("ベンチ　６０／５")).to eq [ "ベンチ", [ [ 60, 5, 1 ] ] ]
    end

    it "A13 0kg は自重（NULL）として扱う" do
      expect(entry_of("懸垂0/10/3")).to eq [ "懸垂", [ [ nil, 10, 3 ] ] ]
      expect(entry_of("懸垂0kg/10/3")).to eq [ "懸垂", [ [ nil, 10, 3 ] ] ]
      expect(entry_of("懸垂0.0/10")).to eq [ "懸垂", [ [ nil, 10, 1 ] ] ]
    end

    it "A14 前後の空白・連続スペース・タブ・CRLF・空行を吸収する" do
      text = "  \tベンチ60/5/3  \r\n\r\n\n スクワット\t80/5 \n\n"
      result = parse(text)
      expect(result).to be_success
      expect(result.entries.map(&:exercise_name)).to eq [ "ベンチ", "スクワット" ]
      expect(result.entries.map(&:line_number)).to eq [ 1, 4 ]
    end

    it "A15 複数行は行ごとに独立に解釈する（1 行 1 種目）" do
      result = parse("ベンチ60/5/3\nスクワット80/5\n懸垂/10/3")
      expect(result).to be_success
      expect(result.entries.map { |e| [ e.exercise_name, e.groups.size ] }).to eq [ [ "ベンチ", 1 ], [ "スクワット", 1 ], [ "懸垂", 1 ] ]
    end

    it "A16 都度送信はパーサーとしては同じ結果（追記は保存フローの責務）" do
      expect(entry_of("ベンチ60/5")).to eq [ "ベンチ", [ [ 60, 5, 1 ] ] ]
      expect(entry_of("ベンチ80/3")).to eq [ "ベンチ", [ [ 80, 3, 1 ] ] ]
    end

    it "A17 上限ぎりぎり（重量 999.9・回数 999・セット 20・20 行）" do
      expect(entry_of("デッドリフト999.9/1")).to eq [ "デッドリフト", [ [ 999.9, 1, 1 ] ] ]
      expect(entry_of("DL999.9kg/1回")).to eq [ "DL", [ [ 999.9, 1, 1 ] ] ]
      expect(entry_of("ベンチ60/999/20")).to eq [ "ベンチ", [ [ 60, 999, 20 ] ] ]
      expect(parse(Array.new(20) { |i| "種目#{i} 60/5" }.join("\n"))).to be_success
    end
  end

  describe "拒否（R）" do
    it "R1 種目名がない" do
      expect(reasons_of("60/5/3")).to eq [ :missing_exercise_name ]
      expect(reasons_of("/10/3")).to eq [ :missing_exercise_name ]
    end

    it "R2 回数がない（`/` がない）" do
      expect(reasons_of("ベンチ60")).to eq [ :missing_group ]
      expect(reasons_of("ベンチ 60kg")).to eq [ :missing_group ]
    end

    it "R3 旧・正式記法は解釈しない（推測補正しない）" do
      expect(reasons_of("ベンチ 60 5 3")).to eq [ :missing_group ]
      expect(reasons_of("ベンチ 60kg 5回 3セット")).to eq [ :missing_group ]
    end

    it "R4 グループは 2 または 3 要素、回数は空にできない" do
      [ "ベンチ60/5/3/2", "ベンチ60/", "ベンチ60//3", "ベンチ/", "ベンチ//3" ].each do |text|
        expect(reasons_of(text)).to eq([ :invalid_group ]), text
      end
    end

    it "R5 単位が対応する位置にない" do
      [ "ベンチ60回/5kg/3セット", "ベンチ60/5セット/3回", "ベンチ60/5/3回" ].each do |text|
        expect(reasons_of(text)).to eq([ :invalid_group ]), text
      end
    end

    it "R6 未知の単位" do
      [ "ベンチ60kg/5/3s", "ベンチ60/5/×3", "ベンチ60/5個/3", "ベンチ60/5/3本", "ベンチ60lb/5" ].each do |text|
        expect(reasons_of(text)).to eq([ :invalid_group ]), text
      end
    end

    it "R7 グループとして解釈できないトークン" do
      expect(reasons_of("ベンチ60/5/3 メモ")).to eq [ :invalid_group ]
      expect(reasons_of("ベンチ60/5/3 3")).to eq [ :invalid_group ]
    end

    it "R8 重量の形式（小数 1 桁・カンマ・負数・先頭/末尾のドット）" do
      [ "ベンチ60.25/5", "ベンチ.5/5", "ベンチ60./5", "ベンチ62,5/5", "ベンチ-5/5" ].each do |text|
        expect(parse(text)).not_to be_success, text
      end
    end

    it "R9 重量は 1000 未満" do
      expect(reasons_of("ベンチ1000/5")).to eq [ :weight_out_of_range ]
      expect(reasons_of("ベンチ1000kg/5")).to eq [ :weight_out_of_range ]
    end

    it "R10 回数は正の整数" do
      expect(reasons_of("ベンチ60/0")).to eq [ :reps_out_of_range ]
      expect(reasons_of("ベンチ60/1.5")).to eq [ :invalid_group ]
      expect(reasons_of("ベンチ60/-3")).to eq [ :invalid_group ]
    end

    it "R11 回数は 999 まで" do
      expect(reasons_of("ベンチ60/1000")).to eq [ :reps_out_of_range ]
    end

    it "R12 セット数は 1〜20" do
      expect(reasons_of("ベンチ60/5/0")).to eq [ :sets_out_of_range ]
      expect(reasons_of("ベンチ60/5/21")).to eq [ :sets_out_of_range ]
    end

    it "R13 複数行のうち 1 行が失敗したら全体が失敗（成功した行も entries に含めない）" do
      result = parse("ベンチ60/5/3\nスクワット 80 5\n懸垂/10/3")

      expect(result).not_to be_success
      expect(result.entries).to be_empty
      expect(result.errors.map { |e| [ e.line_number, e.line, e.reason ] }).to eq [ [ 2, "スクワット 80 5", :missing_group ] ]
    end

    it "R14 21 行以上" do
      result = parse(Array.new(21) { |i| "種目#{i} 60/5" }.join("\n"))

      expect(result).not_to be_success
      expect(result.errors.map(&:reason)).to eq [ :too_many_lines ]
    end

    it "空のメッセージ（空白のみ）は失敗" do
      expect(reasons_of("  \n \t")).to eq [ :empty_message ]
    end
  end

  describe "注意書き: 種目名が数字で終わる場合" do
    it "スペースがあれば末尾の数字は種目名に含める" do
      expect(entry_of("ベンチ2 60/5")).to eq [ "ベンチ2", [ [ 60, 5, 1 ] ] ]
    end

    it "スペースがなければ数字は重量に吸収される（仕様書 4.2.2 の注意書きどおり）" do
      expect(entry_of("ベンチ260/5")).to eq [ "ベンチ", [ [ 260, 5, 1 ] ] ]
    end
  end

  # 公開 API は call のみ。module_function は後続の def をすべて公開特異メソッドにするため、
  # 補助メソッドが外から呼べないことを明示しておく（PR #66 レビュー指摘）
  describe "公開 API" do
    it "補助メソッド（parse_line / split_name_and_group / group_like? / parse_group）は外から呼べない" do
      %i[parse_line split_name_and_group group_like? parse_group].each do |name|
        expect(described_class).not_to respond_to(name), "#{name} is public"
      end
      expect(described_class).to respond_to(:call)
    end
  end
end
