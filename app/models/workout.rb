class Workout < ApplicationRecord
  belongs_to :user
  # 記録は物理削除（SPEC 4.3）。workout 削除時は配下のセットも削除する。
  has_many :workout_sets, dependent: :destroy

  # 一意性は 1 ユーザー 1 日 1 レコード（SPEC 4.5）。DB の unique index と二層で担保する。
  validates :performed_on, presence: true, uniqueness: { scope: :user_id }

  # 一覧表示用の集計（SPEC 4.4 画面 3: 種目数・総セット数）。行ごとの追加クエリを避ける。
  scope :with_set_stats, -> {
    left_joins(:workout_sets)
      .select("workouts.*",
              "COUNT(DISTINCT workout_sets.exercise_id) AS exercise_count",
              "COUNT(workout_sets.id) AS total_set_count")
      .group(:id)
  }
  scope :performed_in, ->(month) { where(performed_on: month.all_month) }

  # LINE 入力は当日の workout に追記する（SPEC 4.2.2: 1 ユーザー 1 日 1 レコード）。
  # 検索と作成の間に別処理（同一ユーザーの並行入力）が同日の行を作った場合は検索し直してその行を返す
  # （SPEC 4.5「リトライまたは一時的な障害として扱う」のうちリトライ側）。衝突は 2 経路で現れる:
  #   - 相手がコミット済み: 一意性のモデル検証がその行を見て RecordInvalid（DB 制約より先に検証が走る）
  #   - 相手が未コミット: 検証は通り INSERT が相手のコミットを待って RecordNotUnique。create_or_find_by! が
  #     savepoint 内で INSERT するため、トランザクションは中断せず検索に切り替わる
  def self.find_or_create_for_day!(user:, performed_on:)
    user.workouts.find_by(performed_on: performed_on) || user.workouts.create_or_find_by!(performed_on: performed_on)
  # rescueは並行処理による競合対策
  rescue ActiveRecord::RecordInvalid
    user.workouts.find_by!(performed_on: performed_on)
  end

  # 同一 workout×種目の最大 set_number の次を振って追記する（SPEC 4.5。例: 1,2,3 の後は 4,5）。
  # 並行入力（LINE と Web 等）とは workout 行の SELECT FOR UPDATE で直列化する
  # （2026-08-14 決定。制約違反リトライ方式は中断トランザクションの回復が複雑なため不採用）。
  def append_set(exercise:, **attributes)
    with_lock do
      # 自動採番を後置し、attributes に set_number が紛れても上書きされないようにする
      workout_sets.create(**attributes, exercise: exercise, set_number: next_set_number(exercise))
    end
  end

  # 同一種目の複数セットを左から順に採番して一括追記する（LINE の一括保存・SPEC 4.2.2）。
  # 採番規則と行ロックは append_set と同じ。1 件でも無効なら RecordInvalid を投げ、
  # 同じ呼び出しで作ったセットはトランザクションごと巻き戻る（部分保存しない・SPEC 4.2.3）
  def append_sets!(exercise:, sets:)
    with_lock do
      number = next_set_number(exercise)
      sets.map do |attributes|
        workout_sets.create!(**attributes, exercise: exercise, set_number: number).tap { number += 1 }
      end
    end
  end

  # セット削除時に同一 workout×種目の後続セットを繰り上げ、歯抜けを作らない（SPEC 4.5）。
  # 削除と繰り上げは同一トランザクションで行い、採番（append_set）と同じ行ロックで直列化する。
  # 繰り上げは小さい番号から順に更新するため、空いた枠に詰める形になり一意制約と衝突しない。
  def remove_set(workout_set)
    unless workout_set.workout_id == id
      raise ArgumentError, "workout_set does not belong to this workout"
    end

    with_lock do
      workout_set.destroy!
      followers = workout_sets.where(exercise_id: workout_set.exercise_id)
                              .where(set_number: (workout_set.set_number + 1)..)
                              .order(:set_number)
      followers.each { |set| set.update!(set_number: set.set_number - 1) }
      workout_set
    end
  end

  private

  # 呼び出し側で with_lock を取っていること（採番の直列化）
  def next_set_number(exercise)
    workout_sets.where(exercise: exercise).maximum(:set_number).to_i + 1
  end
end
