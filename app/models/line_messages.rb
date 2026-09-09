# Bot が返すテキスト（SPEC 4.2.1 / 4.2.3）。文言を一箇所に集め、挨拶とヘルプで入力案内を共有する
module LineMessages
  module_function

  # 記録フォーマット（SPEC 4.2.2）とコマンドの案内。follow の挨拶と「ヘルプ」（11.1）で共用
  def input_guide
    <<~TEXT.chomp
      【記録の書き方】1 行 1 種目
      ベンチプレス 60kg 10回 3セット
      スクワット 80kg 5回（セット数を省略すると 1 セット）
      懸垂 10回 3セット（自重種目は重量を省略可）

      「今日」で当日の記録、「履歴」で直近 7 日の記録、「ヘルプ」でこの案内を表示します。
    TEXT
  end

  # 新規の友だち追加（SPEC 4.2.1 follow・新規）
  def welcome
    "友だち追加ありがとうございます！\nトレーニングの記録をこのトークに送るだけで保存できます。\n\n#{input_guide}"
  end

  # ブロック解除後の再追加（SPEC 4.2.1 follow・既存）。記録は残っていることを伝える
  def welcome_back
    "おかえりなさい！これまでの記録はそのまま残っています。\n\n#{input_guide}"
  end
end
