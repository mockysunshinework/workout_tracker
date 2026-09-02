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

  # 連携コードは LINE のトークにユーザーが手入力する短いコード（SPEC 4.1.2 命名注記）。
  # 大文字英数字に限定し、照合側（8.3）で入力を upcase して大小文字の打ち間違いを吸収する
  LINE_LINK_CODE_CHARSET = [ *"A".."Z", *"0".."9" ].freeze
  LINE_LINK_CODE_LENGTH = 6
  LINE_LINK_CODE_TTL = 10.minutes

  # 連携コードを発行して返す。再発行はコード・有効期限とも置き換える（SPEC 4.1.2）。
  # 他ユーザーとの衝突（unique 制約違反）は稀だが起こりうるため再生成でリトライする
  def issue_line_link_code!(max_attempts: 5)
    attempts = 0
    begin
      update!(
        line_link_code: generate_line_link_code,
        line_link_code_expires_at: LINE_LINK_CODE_TTL.from_now
      )
      line_link_code
    rescue ActiveRecord::RecordNotUnique
      attempts += 1
      retry if attempts < max_attempts
      raise
    end
  end

  # 連携解除（SPEC 4.1.2: line_user_id の NULL 化）
  def unlink_line!
    update!(line_user_id: nil)
  end

  private

  def generate_line_link_code
    Array.new(LINE_LINK_CODE_LENGTH) { LINE_LINK_CODE_CHARSET.sample(random: SecureRandom) }.join
  end
end
