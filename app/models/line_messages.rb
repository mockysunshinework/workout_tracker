# Bot が返すテキスト（SPEC 4.2.1 / 4.2.3）。文言を一箇所に集め、挨拶とヘルプで入力案内を共有する
module LineMessages
  module_function

  # 記録フォーマット（短縮記法・SPEC 4.2.2 版 3.2）とコマンドの案内。
  # follow の挨拶・「ヘルプ」（11.1）・パース失敗の返信（9.5）・Web ダッシュボードで同じ例を使う。
  # 種目名の例はプリセットの正式名称にする（例をそのまま送れば 9.3 の完全一致で保存できる。
  # 略称の解決はエイリアス（SPEC 10 章 #17・未確定）の領分なので案内では約束しない）
  def input_guide
    <<~TEXT.chomp
      【記録の書き方】1 行 1 種目「種目名 重量/回数/セット数」
      ベンチプレス60/5/3 → 60kg × 5回 × 3セット
      ベンチプレス60/5 → セット数を省略すると 1セット
      ベンチプレス60/5 65/5 70/3 → 重量や回数が変わるときは並べて書く
      懸垂/10/3 → 自重は重量を空にする

      「今日」で当日の記録、「履歴」で直近 7 日の記録、「ヘルプ」でこの案内を表示します。
    TEXT
  end

  # 新規の友だち追加（SPEC 4.2.1 follow・新規）
  # 保存内容のエコーバック（SPEC 4.2.3）。グループごとに「重量×回数×セット数」を個別に列挙し、
  # 合算や省略で打ち間違い（例: `懸垂/10 /3` のスペース）が見えなくならないようにする（9.1・2026-09-16 決定）
  def recorded(saved)
    lines = saved.entries.map do |entry|
      groups = entry.groups.map { |g| "#{format_weight(g.weight_kg)}×#{g.reps}回×#{g.sets}セット" }.join(" / ")
      "#{entry.exercise_name} #{groups}（本日 計#{entry.daily_set_count}セット）"
    end
    <<~TEXT.chomp
      #{saved.performed_on.strftime('%-m/%-d')} の記録を保存しました
      #{lines.join("\n")}
      本日合計 #{saved.total_set_count}セット
    TEXT
  end

  # 自重（nil）は「自重」、それ以外は末尾の .0 を落として kg を付ける（60 → 60kg、62.5 → 62.5kg）
  def format_weight(weight_kg)
    return "自重" if weight_kg.nil?

    "#{weight_kg.to_s('F').delete_suffix('.0')}kg"
  end

  def welcome
    "友だち追加ありがとうございます！\nトレーニングの記録をこのトークに送るだけで保存できます。\n\n#{input_guide}"
  end

  # ブロック解除後の再追加（SPEC 4.2.1 follow・既存）。記録は残っていることを伝える
  def welcome_back
    "おかえりなさい！これまでの記録はそのまま残っています。\n\n#{input_guide}"
  end
end
