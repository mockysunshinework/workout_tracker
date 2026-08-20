require "rails_helper"

# 5.2 記録一覧画面（SPEC 4.4 画面 3）: 日付降順の一覧（日付・種目数・総セット数）と月フィルタ
RSpec.describe "Workouts index", type: :request do
  describe "認証ガード" do
    it "未ログインで一覧にアクセスするとログイン画面へリダイレクトする" do
      get workouts_path

      expect(response).to redirect_to(new_user_session_path)
    end
  end

  describe "一覧表示" do
    let(:user) { create(:user) }

    before { sign_in user }

    # 行のセル（日付・種目数・総セット数）をテキストで返す
    def cells_for(workout)
      response.parsed_body.css("#workout_#{workout.id} td").map { |td| td.text.strip }
    end

    it "日付降順で表示される" do
      older = create(:workout, user: user, performed_on: Date.new(2026, 8, 13))
      newer = create(:workout, user: user, performed_on: Date.new(2026, 8, 14))

      get workouts_path

      ids = response.parsed_body.css("tbody tr").map { |tr| tr["id"] }
      expect(ids).to eq [ "workout_#{newer.id}", "workout_#{older.id}" ]
    end

    it "日付・種目数・総セット数が表示される" do
      workout = create(:workout, user: user, performed_on: Date.new(2026, 8, 14))
      bench = create(:exercise, user: user, name: "ベンチプレス")
      squat = create(:exercise, user: user, name: "スクワット")
      create(:workout_set, workout: workout, exercise: bench, set_number: 1)
      create(:workout_set, workout: workout, exercise: bench, set_number: 2)
      create(:workout_set, workout: workout, exercise: squat, set_number: 1)

      get workouts_path

      expect(cells_for(workout)).to eq [ "2026-08-14", "2", "3" ]
    end

    it "セットのない記録は 0 種目・0 セットとして表示される" do
      workout = create(:workout, user: user, performed_on: Date.new(2026, 8, 13))

      get workouts_path

      expect(cells_for(workout)).to eq [ "2026-08-13", "0", "0" ]
    end

    it "他ユーザーの記録は表示されない" do
      mine = create(:workout, user: user, performed_on: Date.new(2026, 8, 13))
      others = create(:workout, performed_on: Date.new(2026, 8, 13))

      get workouts_path

      expect(response.parsed_body.css("#workout_#{mine.id}")).to be_present
      expect(response.parsed_body.css("#workout_#{others.id}")).to be_empty
    end
  end

  describe "月フィルタ" do
    let(:user) { create(:user) }
    let!(:july) { create(:workout, user: user, performed_on: Date.new(2026, 7, 31)) }
    let!(:august) { create(:workout, user: user, performed_on: Date.new(2026, 8, 1)) }

    before { sign_in user }

    it "month 指定でその月の記録だけに絞られる" do
      get workouts_path(month: "2026-07")

      ids = response.parsed_body.css("tbody tr").map { |tr| tr["id"] }
      expect(ids).to eq [ "workout_#{july.id}" ]
    end

    it "month 未指定なら全件表示する" do
      get workouts_path

      ids = response.parsed_body.css("tbody tr").map { |tr| tr["id"] }
      expect(ids).to contain_exactly("workout_#{july.id}", "workout_#{august.id}")
    end

    it "不正な month は無視して全件表示する" do
      get workouts_path(month: "invalid")

      ids = response.parsed_body.css("tbody tr").map { |tr| tr["id"] }
      expect(ids).to contain_exactly("workout_#{july.id}", "workout_#{august.id}")
    end
  end
end
