# LINE のテキストがコマンド（SPEC 4.2.1）かどうかを判定する。コマンドは記録より先に判定し、
# 一致したテキストは記録として扱わない。LINE SDK の型は受け取らない（SPEC 2.3 の境界）
module LineCommand
  COMMANDS = { "ヘルプ" => :help }.freeze

  module_function

  # 一致したコマンドのシンボル、一致しなければ nil。本文全体がコマンド名と一致した場合だけを対象にし、
  # 前後の空白と全角・半角の違い（NFKC）は無視する。「ヘルプお願いします」のような文は一致させない
  def match(text)
    COMMANDS[text.unicode_normalize(:nfkc).strip]
  end
end
