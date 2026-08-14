class WorkoutSet < ApplicationRecord
  belongs_to :workout
  belongs_to :exercise

  validates :reps, numericality: { only_integer: true, greater_than: 0 }
  validates :set_number, numericality: { only_integer: true, greater_than: 0 }
  # 同一 workout×種目内の連番（SPEC 4.5）。DB の unique index と二層で担保する。
  validates :set_number, uniqueness: { scope: [ :workout_id, :exercise_id ] }
  # 上限は列型 decimal(5,1) に合わせる。NULL の可否は種目の bodyweight で決まるため別検証。
  validates :weight_kg, numericality: { greater_than_or_equal_to: 0, less_than: 1000 },
                        allow_nil: true
  validate :weight_kg_required_unless_bodyweight

  private

  # bodyweight は「重量入力の省略を許すか」（SPEC 4.5）。
  # 自重種目（true）のみ weight_kg を省略でき、true でも重量は入力できる。
  def weight_kg_required_unless_bodyweight
    return unless weight_kg.nil?
    return if exercise&.bodyweight?

    errors.add(:weight_kg, :blank)
  end
end
