require "rails_helper"

RSpec.describe Workout, type: :model do
  describe "factory" do
    it "有効な factory を持つ" do
      expect(build(:workout)).to be_valid
    end
  end

  describe "performed_on の検証" do
    it "performed_on がないと無効" do
      workout = build(:workout, performed_on: nil)

      expect(workout).to be_invalid
      expect(workout.errors[:performed_on]).to be_present
    end

    it "同一ユーザー同一日の 2 件目は無効（1 ユーザー 1 日 1 レコード）" do
      user = create(:user)
      create(:workout, user: user, performed_on: Date.new(2026, 8, 13))
      duplicate = build(:workout, user: user, performed_on: Date.new(2026, 8, 13))

      expect(duplicate).to be_invalid
      expect(duplicate.errors[:performed_on]).to be_present
    end

    it "同一日でもユーザーが異なれば有効" do
      create(:workout, performed_on: Date.new(2026, 8, 13))
      other = build(:workout, performed_on: Date.new(2026, 8, 13))

      expect(other).to be_valid
    end

    it "同一ユーザーでも日付が異なれば有効" do
      user = create(:user)
      create(:workout, user: user, performed_on: Date.new(2026, 8, 13))
      next_day = build(:workout, user: user, performed_on: Date.new(2026, 8, 14))

      expect(next_day).to be_valid
    end
  end

  describe "note" do
    it "note は省略できる" do
      expect(build(:workout, note: nil)).to be_valid
    end
  end

  describe "関連" do
    it "user から workouts を辿れる" do
      workout = create(:workout)

      expect(workout.user.workouts).to contain_exactly(workout)
    end
  end

  describe "#append_set（セット採番・SPEC 4.5）" do
    let(:user) { create(:user) }
    let(:workout) { create(:workout, user: user) }
    let(:exercise) { create(:exercise, user: user) }

    it "最初のセットは set_number 1 で追記される" do
      set = workout.append_set(exercise: exercise, reps: 10, weight_kg: 60.0)

      expect(set).to be_persisted
      expect(set.set_number).to eq 1
    end

    it "既存 1,2,3 の後の追記は 4,5 になる（仕様書 4.5 の例）" do
      (1..3).each do |n|
        create(:workout_set, workout: workout, exercise: exercise, set_number: n)
      end

      first = workout.append_set(exercise: exercise, reps: 10, weight_kg: 60.0)
      second = workout.append_set(exercise: exercise, reps: 8, weight_kg: 60.0)

      expect([ first.set_number, second.set_number ]).to eq [ 4, 5 ]
    end

    it "採番は種目ごとに独立する" do
      other_exercise = create(:exercise, user: user)
      create(:workout_set, workout: workout, exercise: exercise, set_number: 1)

      set = workout.append_set(exercise: other_exercise, reps: 10, weight_kg: 40.0)

      expect(set.set_number).to eq 1
    end

    it "採番は workout ごとに独立する" do
      other_workout = create(:workout, user: user)
      create(:workout_set, workout: other_workout, exercise: exercise, set_number: 3)

      set = workout.append_set(exercise: exercise, reps: 10, weight_kg: 60.0)

      expect(set.set_number).to eq 1
    end

    it "歯抜けがある場合も「最大の次」を振る（1,3 の次は 4）" do
      create(:workout_set, workout: workout, exercise: exercise, set_number: 1)
      create(:workout_set, workout: workout, exercise: exercise, set_number: 3)

      set = workout.append_set(exercise: exercise, reps: 10, weight_kg: 60.0)

      expect(set.set_number).to eq 4
    end

    it "attributes で set_number を渡しても自動採番が優先される" do
      create(:workout_set, workout: workout, exercise: exercise, set_number: 1)

      set = workout.append_set(exercise: exercise, reps: 10, weight_kg: 60.0, set_number: 99)

      expect(set.set_number).to eq 2
    end

    it "バリデーションエラー時は保存せず、エラー付きのレコードを返す" do
      barbell = create(:exercise, user: user, bodyweight: false)

      set = workout.append_set(exercise: barbell, reps: 10, weight_kg: nil)

      expect(set).not_to be_persisted
      expect(set.errors[:weight_kg]).to be_present
      expect(workout.workout_sets.count).to eq 0
    end
  end

  # 9.4 LINE 入力の保存フロー用（SPEC 4.2.2 / 4.5）
  describe ".find_or_create_for_day!（当日 workout の取得または作成）" do
    let(:user) { create(:user) }
    let(:day) { Date.new(2026, 9, 18) }

    it "同一ユーザー同一日の workout があればそれを返す" do
      existing = create(:workout, user: user, performed_on: day)

      expect { described_class.find_or_create_for_day!(user: user, performed_on: day) }.not_to change(described_class, :count)
      expect(described_class.find_or_create_for_day!(user: user, performed_on: day)).to eq existing
    end

    it "なければ作成して返す" do
      workout = nil
      expect { workout = described_class.find_or_create_for_day!(user: user, performed_on: day) }
        .to change(described_class, :count).by(1)
      expect(workout).to have_attributes(user: user, performed_on: day)
    end

    it "他ユーザーの同日 workout は返さない" do
      other_user = create(:user)
      create(:workout, user: other_user, performed_on: day)

      workout = described_class.find_or_create_for_day!(user: user, performed_on: day)
      expect(workout.user).to eq user
    end

    it "検索と作成の間に別処理が同日 workout を作っていても（一意制約違反）、その行を返す" do
      # find_by が nil を返した直後に別接続が INSERT した状況を、検索だけ空振りさせて再現する
      workouts = user.workouts
      allow(user).to receive(:workouts).and_return(workouts)
      allow(workouts).to receive(:find_by).with(performed_on: day).and_return(nil)
      existing = create(:workout, user: user, performed_on: day)

      expect(described_class.find_or_create_for_day!(user: user, performed_on: day)).to eq existing
    end
  end

  describe "#append_sets!（同一種目の複数セット一括追記・SPEC 4.2.2）" do
    let(:user) { create(:user) }
    let(:workout) { create(:workout, user: user) }
    let(:exercise) { create(:exercise, user: user) }

    it "左から順に採番して追記し、保存したセットを返す" do
      sets = workout.append_sets!(exercise: exercise, sets: [ { weight_kg: 60, reps: 5 }, { weight_kg: 65, reps: 3 } ])

      expect(sets.map { |s| [ s.set_number, s.weight_kg, s.reps ] }).to eq [ [ 1, 60, 5 ], [ 2, 65, 3 ] ]
      expect(sets).to all(be_persisted)
    end

    it "既存 1,2,3 の後は 4,5 になる（同日追記の採番継続）" do
      (1..3).each { |n| create(:workout_set, workout: workout, exercise: exercise, set_number: n) }

      sets = workout.append_sets!(exercise: exercise, sets: [ { weight_kg: 60, reps: 5 }, { weight_kg: 60, reps: 5 } ])

      expect(sets.map(&:set_number)).to eq [ 4, 5 ]
    end

    it "1 件でも無効なら RecordInvalid を投げ、同じ呼び出しのセットは 1 件も残らない" do
      # 自重でない種目に重量なし（weight_kg 必須）を 2 件目に混ぜる
      expect {
        workout.append_sets!(exercise: exercise, sets: [ { weight_kg: 60, reps: 5 }, { weight_kg: nil, reps: 5 } ])
      }.to raise_error(ActiveRecord::RecordInvalid)

      expect(workout.workout_sets.count).to eq 0
    end
  end

  describe "#remove_set（削除時の繰り上げ・SPEC 4.5）" do
    let(:user) { create(:user) }
    let(:workout) { create(:workout, user: user) }
    let(:exercise) { create(:exercise, user: user) }

    def create_sets(*numbers)
      numbers.map do |n|
        create(:workout_set, workout: workout, exercise: exercise, set_number: n)
      end
    end

    it "1,2,3 から 2 を削除すると 1,2 に詰まる（完了条件の例）" do
      first, second, third = create_sets(1, 2, 3)

      workout.remove_set(second)

      expect(workout.workout_sets.order(:set_number).pluck(:id, :set_number))
        .to eq [ [ first.id, 1 ], [ third.id, 2 ] ]
    end

    it "先頭の 1 を削除すると後続がすべて繰り上がる" do
      first, second, third = create_sets(1, 2, 3)

      workout.remove_set(first)

      expect(workout.workout_sets.order(:set_number).pluck(:id, :set_number))
        .to eq [ [ second.id, 1 ], [ third.id, 2 ] ]
    end

    it "末尾の 3 を削除しても他のセットは変わらない" do
      first, second, third = create_sets(1, 2, 3)

      workout.remove_set(third)

      expect(workout.workout_sets.order(:set_number).pluck(:id, :set_number))
        .to eq [ [ first.id, 1 ], [ second.id, 2 ] ]
    end

    it "削除対象のレコードは物理削除される" do
      set, = create_sets(1)

      workout.remove_set(set)

      expect(WorkoutSet.exists?(set.id)).to be false
    end

    it "別種目のセットには影響しない" do
      other_exercise = create(:exercise, user: user)
      other_set = create(:workout_set, workout: workout, exercise: other_exercise, set_number: 2)
      target, = create_sets(1)

      workout.remove_set(target)

      expect(other_set.reload.set_number).to eq 2
    end

    it "別 workout のセットを渡すと ArgumentError になり、何も変更されない" do
      other_workout = create(:workout, user: user)
      foreign_set = create(:workout_set, workout: other_workout, exercise: exercise, set_number: 1)
      create_sets(1, 2)

      expect { workout.remove_set(foreign_set) }.to raise_error(ArgumentError)

      expect(WorkoutSet.exists?(foreign_set.id)).to be true
      expect(workout.workout_sets.order(:set_number).pluck(:set_number)).to eq [ 1, 2 ]
    end

    it "繰り上げに失敗した場合は削除もロールバックされる（同一トランザクション）" do
      _first, second, third = create_sets(1, 2, 3)
      allow_any_instance_of(WorkoutSet)
        .to receive(:update!).and_raise(ActiveRecord::RecordInvalid)

      expect { workout.remove_set(second) }.to raise_error(ActiveRecord::RecordInvalid)

      expect(workout.workout_sets.order(:set_number).pluck(:set_number)).to eq [ 1, 2, 3 ]
      expect(WorkoutSet.exists?(second.id)).to be true
      expect(third.reload.set_number).to eq 3
    end
  end
end
