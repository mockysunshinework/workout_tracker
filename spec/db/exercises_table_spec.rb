require "rails_helper"

# Exercise モデルは 3.4 で実装するため、ここでは DB 制約を生 SQL で直接検証する。
RSpec.describe "exercises テーブル" do
  # optional に渡さなかった列は INSERT 文から除外する。
  # 常に列を並べるとキーワード引数の既定値が入ってしまい、
  # DB 側の default を検証できなくなるため。
  def insert_exercise(user_id:, normalized_name:, name: "テスト種目", **optional)
    unknown = optional.keys - %i[category bodyweight]
    raise ArgumentError, "unknown column: #{unknown.join(", ")}" if unknown.any?

    values = { user_id: user_id, name: name, normalized_name: normalized_name, **optional }
    columns = values.keys.join(", ")
    placeholders = Array.new(values.size, "?").join(", ")

    sql = ActiveRecord::Base.sanitize_sql_array([
      "INSERT INTO exercises (#{columns}, created_at, updated_at) " \
      "VALUES (#{placeholders}, NOW(), NOW())",
      *values.values
    ])
    ActiveRecord::Base.connection.execute(sql)
  end

  describe "[user_id, normalized_name] の一意制約" do
    it "プリセット同士（user_id が NULL）の同名を DB が拒否する" do
      insert_exercise(user_id: nil, normalized_name: "ベンチプレス")

      expect {
        insert_exercise(user_id: nil, normalized_name: "ベンチプレス")
      }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "同一ユーザー内の同名を DB が拒否する" do
      user = create(:user)
      insert_exercise(user_id: user.id, normalized_name: "マイ種目")

      expect {
        insert_exercise(user_id: user.id, normalized_name: "マイ種目")
      }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "ユーザーが異なれば同名を登録できる" do
      user_a = create(:user)
      user_b = create(:user)
      insert_exercise(user_id: user_a.id, normalized_name: "マイ種目")

      expect {
        insert_exercise(user_id: user_b.id, normalized_name: "マイ種目")
      }.not_to raise_error
    end

    it "プリセットと同名のユーザー独自種目を登録できる" do
      user = create(:user)
      insert_exercise(user_id: nil, normalized_name: "ベンチプレス")

      expect {
        insert_exercise(user_id: user.id, normalized_name: "ベンチプレス")
      }.not_to raise_error
    end
  end

  describe "カラム定義" do
    it "bodyweight と category を省略すると DB の既定値が入る" do
      # 列自体を INSERT に含めないことで、DB 側の default を検証する
      insert_exercise(user_id: nil, normalized_name: "ベンチプレス")

      row = ActiveRecord::Base.connection.select_one(
        "SELECT bodyweight, category FROM exercises WHERE normalized_name = 'ベンチプレス'"
      )
      expect(row["bodyweight"]).to be(false)
      expect(row["category"]).to be_nil
    end

    it "bodyweight と category を明示すればその値が入る" do
      insert_exercise(user_id: nil, normalized_name: "懸垂", bodyweight: true, category: "背中")

      row = ActiveRecord::Base.connection.select_one(
        "SELECT bodyweight, category FROM exercises WHERE normalized_name = '懸垂'"
      )
      expect(row["bodyweight"]).to be(true)
      expect(row["category"]).to eq("背中")
    end

    it "name が NULL の行を DB が拒否する" do
      expect {
        insert_exercise(user_id: nil, name: nil, normalized_name: "ベンチプレス")
      }.to raise_error(ActiveRecord::NotNullViolation)
    end

    it "normalized_name が NULL の行を DB が拒否する" do
      expect {
        insert_exercise(user_id: nil, normalized_name: nil)
      }.to raise_error(ActiveRecord::NotNullViolation)
    end

    it "存在しない user_id の行を DB が拒否する" do
      expect {
        insert_exercise(user_id: 0, normalized_name: "マイ種目")
      }.to raise_error(ActiveRecord::InvalidForeignKey)
    end
  end
end
