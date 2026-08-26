require "rails_helper"

# 6.2 グラフデータ JSON エンドポイント（SPEC 4.4）。集計本体は 6.1 の unit spec で検証済みのため、
# ここではエンドポイントの契約（認証・スコープ・パラメータ・JSON 形）を検証する。
RSpec.describe "Charts", type: :request do
  let(:user) { create(:user) }
  let(:exercise) { create(:exercise, user: user, name: "ベンチプレス") }

  def add_set(date, weight, reps)
    workout = Workout.find_or_create_by!(user: user, performed_on: date)
    create(:workout_set, workout: workout, exercise: exercise,
           weight_kg: weight, reps: reps,
           set_number: workout.workout_sets.where(exercise: exercise).count + 1)
  end

  describe "GET /charts/exercise_progress" do
    it "未ログインはログイン画面へリダイレクトする" do
      get charts_exercise_progress_path(exercise_id: exercise.id)

      expect(response).to redirect_to(new_user_session_path)
    end

    context "ログイン済み" do
      before { sign_in user }

      it "指定種目の日付ごとの最大重量と推定 1RM を JSON で返す" do
        add_set(Date.current - 10, 100, 10)
        add_set(Date.current - 5, 90, 12)

        get charts_exercise_progress_path(exercise_id: exercise.id)

        expect(response).to have_http_status(:ok)
        json = response.parsed_body
        expect(json["exercise_id"]).to eq exercise.id
        expect(json["series"]).to eq [
          { "date" => (Date.current - 10).iso8601, "max_weight" => 100.0, "estimated_one_rm" => 133.3 },
          { "date" => (Date.current - 5).iso8601, "max_weight" => 90.0, "estimated_one_rm" => 126.0 }
        ]
      end

      it "months=1 で期間を絞れる（範囲外の記録は含めない）" do
        add_set(Date.current - 2.months, 100, 5)
        add_set(Date.current - 10, 80, 5)

        get charts_exercise_progress_path(exercise_id: exercise.id, months: 1)

        dates = response.parsed_body["series"].map { |row| row["date"] }
        expect(dates).to eq [ (Date.current - 10).iso8601 ]
      end

      it "months 未指定は 3 ヶ月分を返す（仕様書 4.4 の既定）" do
        add_set(Date.current - 2.months, 100, 5)
        add_set(Date.current - 4.months, 120, 5)

        get charts_exercise_progress_path(exercise_id: exercise.id)

        dates = response.parsed_body["series"].map { |row| row["date"] }
        expect(dates).to eq [ (Date.current - 2.months).iso8601 ]
      end

      it "許可外の months は既定の 3 ヶ月にフォールバックする" do
        add_set(Date.current - 2.months, 100, 5)

        get charts_exercise_progress_path(exercise_id: exercise.id, months: 12)

        expect(response.parsed_body["series"].size).to eq 1
      end

      it "プリセット種目も指定できる" do
        preset = create(:exercise, :preset, name: "スクワット")
        workout = create(:workout, user: user, performed_on: Date.current - 3)
        create(:workout_set, workout: workout, exercise: preset,
               weight_kg: 80, reps: 5, set_number: 1)

        get charts_exercise_progress_path(exercise_id: preset.id)

        expect(response.parsed_body["series"].size).to eq 1
      end

      it "他ユーザーの種目は 404 になる" do
        others_exercise = create(:exercise, name: "他人の種目")

        get charts_exercise_progress_path(exercise_id: others_exercise.id)

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe "GET /charts/training_frequency" do
    it "未ログインはログイン画面へリダイレクトする" do
      get charts_training_frequency_path

      expect(response).to redirect_to(new_user_session_path)
    end

    context "ログイン済み" do
      before { sign_in user }

      it "月ごとの実施日数を JSON で返す（unit 未指定は month）" do
        create(:workout, user: user, performed_on: Date.current - 3)
        create(:workout, user: user, performed_on: Date.current - 4)

        get charts_training_frequency_path

        expect(response).to have_http_status(:ok)
        json = response.parsed_body
        expect(json["unit"]).to eq "month"
        expect(json["counts"].sum { |row| row["days"] }).to eq 2
      end

      it "unit=week で週ごとの実施日数を返す" do
        get charts_training_frequency_path(unit: "week")

        expect(response.parsed_body["unit"]).to eq "week"
      end

      it "許可外の unit は month にフォールバックする" do
        get charts_training_frequency_path(unit: "day")

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body["unit"]).to eq "month"
      end

      it "他ユーザーの記録は集計に含めない" do
        other_user = create(:user)
        # 日付を分けておく: 同日だと「重複を除いた日付数」を数える実装に変わった場合、
        # 混入しても合計が変わらず検出できない
        create(:workout, user: other_user, performed_on: Date.current - 4)
        create(:workout, user: user, performed_on: Date.current - 3)

        get charts_training_frequency_path

        expect(response.parsed_body["counts"].sum { |row| row["days"] }).to eq 1
      end
    end
  end
end
