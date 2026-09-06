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

    it "line_user_id が無いと invalid" do
      user = build(:user, line_user_id: nil)
      expect(user).to be_invalid
      expect(user.errors[:line_user_id]).to be_present
    end

    # line_user_id の一意性はモデルでは検証しない（DB の unique index が担保。spec/db/users_line_columns_spec.rb）。
    # 事前 exists? チェックの TOCTOU を避け、衝突は find_or_create_from_line! で吸収する
  end

  # SPEC 4.1.1: 登録操作は無く、follow または初回 LINE Login で line_user_id をキーに自動作成する。
  # 表示名は作成時に設定し、LINE Login 時のみ最新値で更新する（follow 時は再取得しない）
  describe ".find_or_create_from_line!" do
    let(:line_user_id) { "U1234567890abcdef1234567890abcdef" }

    it "未登録の line_user_id なら表示名で User を作成して返す" do
      user = nil
      expect {
        user = User.find_or_create_from_line!(line_user_id: line_user_id, display_name: "もとなが")
      }.to change(User, :count).by(1)

      expect(user).to be_persisted
      expect(user.line_user_id).to eq line_user_id
      expect(user.name).to eq "もとなが"
    end

    it "表示名が取得できない（nil / 空）ならフォールバック名で作成する" do
      user = User.find_or_create_from_line!(line_user_id: line_user_id, display_name: nil)

      expect(user.name).to eq User::FALLBACK_NAME
      expect(User.find_or_create_from_line!(line_user_id: "Uother", display_name: " ").name).to eq User::FALLBACK_NAME
    end

    it "登録済みの line_user_id なら既存 User を返し、表示名は変えない（follow 用の既定）" do
      existing = create(:user, line_user_id: line_user_id, name: "以前の名前")

      user = nil
      expect {
        user = User.find_or_create_from_line!(line_user_id: line_user_id, display_name: "新しい名前")
      }.not_to change(User, :count)

      expect(user).to eq existing
      expect(user.reload.name).to eq "以前の名前"
    end

    it "update_name: true なら既存 User の表示名を最新値に更新する（LINE Login 用）" do
      existing = create(:user, line_user_id: line_user_id, name: "以前の名前")

      user = User.find_or_create_from_line!(line_user_id: line_user_id, display_name: "新しい名前", update_name: true)

      expect(user).to eq existing
      expect(user.reload.name).to eq "新しい名前"
    end

    it "update_name: true でも表示名が取得できなければ既存の名前を保つ" do
      create(:user, line_user_id: line_user_id, name: "以前の名前")

      user = User.find_or_create_from_line!(line_user_id: line_user_id, display_name: nil, update_name: true)

      expect(user.reload.name).to eq "以前の名前"
    end

    it "同一 line_user_id の並行作成は unique 制約で片方が既存を取得する（RecordNotUnique をリトライ）" do
      # 「事前の find では未登録だったが create の直前に別リクエストが作った」状況を再現する:
      # find_by の初回は nil（未登録に見える）→ create! が DB の unique 制約で RecordNotUnique →
      # リトライの find_by!（内部で find_by を呼ぶ）は既存行を返す
      # （with で引数を絞らないのは、find_by! が内部で find_by をハッシュ引数で呼び、キーワード引数の
      #   マッチャと区別されて一致しなくなるため。この example の find_by 呼び出しは 2 回とも同じ引数）
      existing = create(:user, line_user_id: line_user_id, name: "先に作られた")
      allow(User).to receive(:find_by).and_return(nil, existing)

      user = User.find_or_create_from_line!(line_user_id: line_user_id, display_name: "後から")

      expect(user.name).to eq "先に作られた"
      expect(User.where(line_user_id: line_user_id).count).to eq 1
    end
  end

  # SPEC 4.2.1 follow / unfollow。挨拶の種別は呼び出し側（Webhook）が返信文を選ぶために返す
  describe ".follow_from_line!" do
    let(:line_user_id) { "U1234567890abcdef1234567890abcdef" }

    it "未登録なら User を作成し、:welcome を返す" do
      user = kind = nil
      expect {
        user, kind = User.follow_from_line!(line_user_id: line_user_id, display_name: "もとなが")
      }.to change(User, :count).by(1)

      expect(user.name).to eq "もとなが"
      expect(user.line_blocked).to be false
      expect(kind).to eq :welcome
    end

    it "ブロック中（unfollow 済み）の既存ユーザーなら line_blocked を false に戻し、:welcome_back を返す（記録は残る）" do
      existing = create(:user, line_user_id: line_user_id, name: "以前の名前", line_blocked: true)
      workout = create(:workout, user: existing)

      user, kind = User.follow_from_line!(line_user_id: line_user_id, display_name: nil)

      expect(user).to eq existing
      expect(user.reload.line_blocked).to be false
      expect(user.name).to eq "以前の名前"
      expect(kind).to eq :welcome_back
      expect(Workout.exists?(workout.id)).to be true
    end

    it "Web（LINE Login）で先に作られた未ブロックの既存ユーザーが友だち追加した場合は :welcome（初めての LINE 利用として案内する）" do
      create(:user, line_user_id: line_user_id, line_blocked: false)

      _user, kind = User.follow_from_line!(line_user_id: line_user_id, display_name: nil)

      expect(kind).to eq :welcome
    end
  end

  describe ".unfollow_from_line!" do
    let(:line_user_id) { "U1234567890abcdef1234567890abcdef" }

    it "既存ユーザーの line_blocked を true にする（記録は削除しない）" do
      user = create(:user, line_user_id: line_user_id)
      workout = create(:workout, user: user)

      User.unfollow_from_line!(line_user_id: line_user_id)

      expect(user.reload.line_blocked).to be true
      expect(Workout.exists?(workout.id)).to be true
    end

    it "未登録の line_user_id なら何もしない（作成もしない）" do
      expect {
        User.unfollow_from_line!(line_user_id: line_user_id)
      }.not_to change(User, :count)
    end
  end
end
