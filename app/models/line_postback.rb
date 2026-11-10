# Quick Reply の postback `data` の組み立て（SPEC 4.3.1(2) の設計方針・10.2）。
# data には保留 id・操作・種目 id などの識別子だけを入れ、ユーザーが入力した文字列は含めない
# （上限 300 文字の超過を避け、stale postback の無効化は id 再採番で担保するため）。
# 形式はクエリ文字列（`action=choose&pending_id=12&exercise_id=34`）。10.6 の postback 処理で解釈する
module LinePostback
  ACTIONS = %w[choose create cancel alias_confirm alias_decline].freeze

  module_function

  def encode(action:, **ids)
    action = action.to_s
    raise ArgumentError, "unknown postback action: #{action}" unless ACTIONS.include?(action)

    Rack::Utils.build_query({ action: action, **ids })
  end
end
