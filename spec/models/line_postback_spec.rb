require "rails_helper"

# 10.5 postback の data（SPEC 4.3.1(2) の設計方針: 識別子のみを入れ、ユーザー入力は含めない。上限 300 文字）
RSpec.describe LinePostback do
  describe ".encode" do
    it "action と識別子をクエリ文字列にする" do
      expect(described_class.encode(action: :choose, pending_id: 12, exercise_id: 34)).to eq "action=choose&pending_id=12&exercise_id=34"
      expect(described_class.encode(action: :create, pending_id: 12)).to eq "action=create&pending_id=12"
      expect(described_class.encode(action: :cancel, pending_id: 12)).to eq "action=cancel&pending_id=12"
    end

    it "未知の action は拒否する" do
      expect { described_class.encode(action: :delete_everything, pending_id: 1) }.to raise_error(ArgumentError)
    end

    it "300 文字以内に収まる" do
      expect(described_class.encode(action: :alias_confirm, alias_id: 9_223_372_036_854_775_807).length).to be <= 300
    end
  end

  # 10.6 受信した postback の data を解釈する。LINE から届く値は外部入力なので、形式が違えば nil にして捨てる
  describe ".decode" do
    it "encode した data を action と整数の id に戻す" do
      postback = described_class.decode(described_class.encode(action: :choose, pending_id: 12, exercise_id: 34))

      expect(postback.action).to eq "choose"
      expect(postback.ids).to eq({ "pending_id" => 12, "exercise_id" => 34 })
    end

    it "未知の action・action なし・空・nil は nil" do
      expect(described_class.decode("action=delete_everything&pending_id=1")).to be_nil
      expect(described_class.decode("pending_id=1")).to be_nil
      expect(described_class.decode("")).to be_nil
      expect(described_class.decode(nil)).to be_nil
    end

    it "id が数字だけでない data は nil" do
      expect(described_class.decode("action=cancel&pending_id=1%20OR%201=1")).to be_nil
      expect(described_class.decode("action=cancel&pending_id=")).to be_nil
      expect(described_class.decode("action=cancel&pending_id[]=1")).to be_nil
      expect(described_class.decode("action=cancel&pending_id=1&pending_id=2")).to be_nil
    end
  end
end
