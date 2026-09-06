class User < ApplicationRecord
  # The account identity is the LINE account itself (SPEC 4.1). Web sign-in is
  # LINE Login only, so no email/password modules: omniauthable provides the
  # /users/auth/line routes and rememberable keeps the session.
  devise :omniauthable, :rememberable, omniauth_providers: [ :line ]

  # 宣言順に依存あり: ユーザー削除時は workouts（配下の workout_sets ごと）が先に消えることで、
  # exercises の削除制限（使用中は削除不可・restrict_with_error）と衝突しない
  has_many :workouts, dependent: :destroy
  has_many :exercises, dependent: :destroy

  validates :name, presence: true
  # line_user_id の一意性は DB の unique index に任せる（事前 exists? チェックの TOCTOU を避ける。
  # 衝突は find_or_create_from_line! が吸収する）
  validates :line_user_id, presence: true

  # プロフィール取得に同意していない等で表示名が取れない場合の名前（SPEC 4.1.1）
  FALLBACK_NAME = "LINE ユーザー"

  # SPEC 4.1.1: 登録操作は無く、follow または初回 LINE Login のどちらか早い方で
  # line_user_id をキーに自動作成する。表示名は作成時に設定し、LINE Login 時（update_name: true）
  # のみ最新値で更新する。follow 時は再取得しないので既定は更新しない
  def self.find_or_create_from_line!(line_user_id:, display_name:, update_name: false)
    name = display_name.presence

    if (user = find_by(line_user_id: line_user_id))
      user.update!(name: name) if update_name && name && user.name != name
      return user
    end

    create!(line_user_id: line_user_id, name: name || FALLBACK_NAME)
  rescue ActiveRecord::RecordNotUnique
    # follow と LINE Login が初回接触で同時に走ると片方の create が unique 制約で落ちる。
    # 負けた側は勝った側の行を返せばよい（同じ LINE アカウントなので結果は同じ）
    find_by!(line_user_id: line_user_id)
  end
end
