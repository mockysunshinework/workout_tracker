require "rails_helper"

RSpec.describe ExerciseNameNormalizer, type: :model do
  describe ".call" do
    context "Unicode NFKC 正規化" do
      it "半角カナを全角カナに揃える" do
        expect(described_class.call("ﾍﾞﾝﾁﾌﾟﾚｽ")).to eq("ベンチプレス")
      end

      it "全角英数を半角に揃える" do
        expect(described_class.call("ＢＥＮＣＨ１")).to eq("bench1")
      end

      it "分離した濁点・半濁点を合成する" do
        expect(described_class.call("ベンチプレス")).to eq("ベンチプレス")
      end
    end

    context "前後空白の除去" do
      it "前後の半角空白を除去する" do
        expect(described_class.call("  ベンチプレス  ")).to eq("ベンチプレス")
      end

      it "前後の全角空白を除去する" do
        expect(described_class.call("　ベンチプレス　")).to eq("ベンチプレス")
      end

      it "内部の空白は保持する" do
        expect(described_class.call("　ベンチ プレス　")).to eq("ベンチ プレス")
      end
    end

    context "ゼロ幅文字の除去" do
      # NFKC でも strip でも落ちず、目視でも気づけないため個別に除去する
      it "前後のゼロ幅スペース（U+200B）を除去する" do
        expect(described_class.call("\u200Bベンチプレス\u200B")).to eq("ベンチプレス")
      end

      it "文字列中のゼロ幅スペースを除去する" do
        expect(described_class.call("ベンチ\u200Bプレス")).to eq("ベンチプレス")
      end

      it "BOM（U+FEFF）を除去する" do
        expect(described_class.call("\uFEFFベンチプレス")).to eq("ベンチプレス")
      end

      it "ゼロ幅文字と空白が混在しても前後が除去される" do
        expect(described_class.call("\u200B　ベンチプレス　\u200B")).to eq("ベンチプレス")
      end

      it "ゼロ幅文字のみの入力は空文字を返す" do
        expect(described_class.call("\u200B\uFEFF")).to eq("")
      end
    end

    context "ひらがな → カタカナ変換" do
      it "ひらがなをカタカナに変換する" do
        expect(described_class.call("ベンチぷれす")).to eq("ベンチプレス")
      end

      it "小書き文字を変換する" do
        expect(described_class.call("ぁぃぅぇぉっゃゅょ")).to eq("ァィゥェォッャュョ")
      end

      it "ゔ をヴに変換する" do
        expect(described_class.call("ゔ")).to eq("ヴ")
      end

      it "長音記号はそのまま残す" do
        expect(described_class.call("ろーいんぐ")).to eq("ローイング")
      end
    end

    context "英字の小文字化" do
      it "大文字を小文字にする" do
        expect(described_class.call("Bench Press")).to eq("bench press")
      end
    end

    context "仕様書 4.3.1(1) の例" do
      it "「ベンチプレス　」と「ベンチぷれす」が同じ値に正規化される" do
        expect(described_class.call("ベンチプレス　")).to eq("ベンチプレス")
        expect(described_class.call("ベンチぷれす")).to eq("ベンチプレス")
      end
    end

    context "入力が空の場合" do
      # 名前の presence 検証は Exercise モデルの責務（plan.md 3.4）のため、
      # ここでは例外にせず空文字を返す。
      it "空文字は空文字を返す" do
        expect(described_class.call("")).to eq("")
      end

      it "空白のみの入力は空文字を返す" do
        expect(described_class.call("　 　")).to eq("")
      end

      it "nil は空文字を返す" do
        expect(described_class.call(nil)).to eq("")
      end
    end
  end
end
