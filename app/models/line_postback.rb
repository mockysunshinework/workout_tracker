# Quick Reply の postback `data` の組み立て（SPEC 4.3.1(2) の設計方針・10.2）。
# data には保留 id・操作・種目 id などの識別子だけを入れ、ユーザーが入力した文字列は含めない
# （上限 300 文字の超過を避け、stale postback の無効化は id 再採番で担保するため）。
# 形式はクエリ文字列（`action=choose&pending_id=12&exercise_id=34`）。解釈は decode（10.6）
module LinePostback
  ACTIONS = %w[
    choose
    create
    cancel
    alias_confirm
    alias_decline
  ].freeze

  # decode の結果。ids は action 以外のキー → 整数（例: { "pending_id" => 12, "exercise_id" => 34 }）
  Postback = Data.define(:action, :ids)

  module_function

  def encode(action:, **ids)
    action = action.to_s
    raise ArgumentError, "unknown postback action: #{action}" unless ACTIONS.include?(action)

    Rack::Utils.build_query({ action: action, **ids })
  end

  # 受信した data を解釈する。LINE から届く値は外部入力として扱い、未知の action や数字だけでない id は
  # nil を返して捨てる（呼び出し側は無効なボタンとして再入力を案内する）
  def decode(data)
    params = Rack::Utils.parse_query(data.to_s)
    action = params.delete("action")
    return nil unless ACTIONS.include?(action)
    # 値は数字だけの文字列（同じキーの重複は配列になるので弾く）、キーは encode が作る形（英小文字と _）だけ
    return nil unless params.all? { |key, value| key.match?(/\A[a-z_]+\z/) && value.is_a?(String) && value.match?(/\A\d+\z/) }

    Postback.new(action: action, ids: params.transform_values(&:to_i))
  end
end
