# 種目名の表記ゆれを吸収し、照合用の文字列を返す（SPEC 4.3.1(1)）。
# 結果は exercises.normalized_name に保持し、完全一致検索に使う。
#
# 名前の presence 検証は Exercise モデルの責務のため、ここでは
# nil や空白のみの入力を例外にせず空文字を返す。
module ExerciseNameNormalizer
  # ひらがな（ぁ〜ゖ）をカタカナ（ァ〜ヶ）へ写す。
  # ゔ・ゕ・ゖ を含めるため「ん」ではなく「ゖ」までを範囲にする。
  HIRAGANA_RANGE = "ぁ-ゖ".freeze
  KATAKANA_RANGE = "ァ-ヶ".freeze

  # 目視できず NFKC でも strip でも落ちない不可視文字。
  # コピペ入力で混入すると、見た目が同じなのに一致しない種目が生まれる。
  #
  # 内訳: U+200B ZERO WIDTH SPACE 〜 U+200D ZERO WIDTH JOINER（範囲指定）、
  #       U+2060 WORD JOINER、U+FEFF ZERO WIDTH NO-BREAK SPACE（BOM）。
  # リテラルで書くと何が対象か読めず、欠落しても気づけないためエスケープで書く。
  ZERO_WIDTH = /[\u200B-\u200D\u2060\uFEFF]/

  module_function

  def call(name)
    name.to_s
        .unicode_normalize(:nfkc) # 全角英数・半角カナ・分離した濁点を統一する
        .gsub(ZERO_WIDTH, "")     # strip より先に消す。先頭に残ると strip が止まるため
        .strip                    # 全角空白（U+3000）は NFKC が U+0020 に畳むのでここで落ちる
        .tr(HIRAGANA_RANGE, KATAKANA_RANGE)
        .downcase
  end
end
