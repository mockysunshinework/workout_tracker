class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  # 宣言順に依存あり: ユーザー削除時は workouts（配下の workout_sets ごと）が先に消えることで、
  # exercises の削除制限（使用中は削除不可・restrict_with_error）と衝突しない
  has_many :workouts, dependent: :destroy
  has_many :exercises, dependent: :destroy

  validates :name, presence: true
end
