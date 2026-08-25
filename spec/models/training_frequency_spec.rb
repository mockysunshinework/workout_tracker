require "rails_helper"

# 6.1 月間頻度の集計（SPEC 4.4）: 週または月ごとのトレーニング実施日数
RSpec.describe TrainingFrequency do
  let(:user) { create(:user) }

  def add_workout(date)
    create(:workout, user: user, performed_on: date)
  end

  describe ".counts（unit: :month）" do
    it "月ごとの実施日数を期間昇順で返す" do
      add_workout(Date.new(2026, 7, 30))
      add_workout(Date.new(2026, 8, 3))
      add_workout(Date.new(2026, 8, 5))
      add_workout(Date.new(2026, 8, 12))

      counts = described_class.counts(user: user, unit: :month, since: Date.new(2026, 7, 1))

      expect(counts).to eq [
        { period_start: Date.new(2026, 7, 1), days: 1 },
        { period_start: Date.new(2026, 8, 1), days: 3 }
      ]
    end
  end

  describe ".counts（unit: :week）" do
    it "週ごと（月曜起点）の実施日数を期間昇順で返す" do
      add_workout(Date.new(2026, 8, 3))  # 月曜（8/3 の週）
      add_workout(Date.new(2026, 8, 5))  # 水曜（8/3 の週）
      add_workout(Date.new(2026, 8, 12)) # 水曜（8/10 の週）

      counts = described_class.counts(user: user, unit: :week, since: Date.new(2026, 8, 1))

      expect(counts).to eq [
        { period_start: Date.new(2026, 8, 3), days: 2 },
        { period_start: Date.new(2026, 8, 10), days: 1 }
      ]
    end
  end

  describe "共通の絞り込み" do
    it "since より前の記録は含めない" do
      add_workout(Date.new(2026, 7, 31))
      add_workout(Date.new(2026, 8, 1))

      counts = described_class.counts(user: user, unit: :month, since: Date.new(2026, 8, 1))

      expect(counts).to eq [ { period_start: Date.new(2026, 8, 1), days: 1 } ]
    end

    it "他ユーザーの記録は含めない" do
      create(:workout, performed_on: Date.new(2026, 8, 1))
      add_workout(Date.new(2026, 8, 3))

      counts = described_class.counts(user: user, unit: :month, since: Date.new(2026, 8, 1))

      expect(counts).to eq [ { period_start: Date.new(2026, 8, 1), days: 1 } ]
    end

    it "不正な unit は ArgumentError になる" do
      expect {
        described_class.counts(user: user, unit: :day, since: Date.new(2026, 8, 1))
      }.to raise_error(ArgumentError)
    end
  end
end
