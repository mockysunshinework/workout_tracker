require "rails_helper"

RSpec.describe User, type: :model do
  describe "バリデーション" do
    it "有効な属性なら valid" do
      expect(build(:user)).to be_valid
    end

    it "name が無いと invalid" do
      user = build(:user, name: nil)
      expect(user).to be_invalid
      expect(user.errors[:name]).to be_present
    end

    it "email が重複すると invalid" do
      create(:user, email: "dup@example.com")
      user = build(:user, email: "dup@example.com")
      expect(user).to be_invalid
      expect(user.errors[:email]).to be_present
    end
  end

  describe "#issue_line_link_code!（連携コード発行・SPEC 4.1.2）" do
    let(:user) { create(:user) }

    it "6 桁の大文字英数字コードを発行して返し、保存する" do
      code = user.issue_line_link_code!

      expect(code).to match(/\A[A-Z0-9]{6}\z/)
      expect(user.reload.line_link_code).to eq code
    end

    it "有効期限を発行時点の 10 分後に設定する" do
      freeze_time do
        user.issue_line_link_code!

        expect(user.reload.line_link_code_expires_at)
          .to eq(10.minutes.from_now)
      end
    end

    it "再発行するとコードと有効期限が置き換わる" do
      first_code = user.issue_line_link_code!
      first_expiry = user.reload.line_link_code_expires_at

      travel_to(5.minutes.from_now) do
        second_code = user.issue_line_link_code!

        expect(second_code).not_to eq first_code
        expect(user.reload.line_link_code).to eq second_code
        expect(user.line_link_code_expires_at).to be > first_expiry
      end
    end

    it "生成したコードが他ユーザーと衝突したら再生成する（unique 制約でリトライ）" do
      create(:user).update_column(:line_link_code, "AAAAAA")
      allow(user).to receive(:generate_line_link_code).and_return("AAAAAA", "BBBBBB") # and_return に複数の値を渡すと、呼び出し回数ごとに順番に異なる値を返すスタブになる

      code = user.issue_line_link_code!

      expect(code).to eq "BBBBBB"
      expect(user.reload.line_link_code).to eq "BBBBBB"
    end
  end

  describe "#unlink_line!（連携解除・SPEC 4.1.2）" do
    it "line_user_id を NULL 化する" do
      user = create(:user)
      user.update_column(:line_user_id, "U1234567890abcdef1234567890abcdef")

      user.unlink_line!

      expect(user.reload.line_user_id).to be_nil
    end
  end
end
