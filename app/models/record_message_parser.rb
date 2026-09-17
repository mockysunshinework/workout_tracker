# LINE から送られた記録メッセージ（短縮記法・SPEC 4.2.2 版 3.2）を、種目名と
# (重量, 回数, セット数) のグループ列に変換する。DB や種目マスタには触れない純粋な変換で、
# 種目名の解決（エイリアス・候補提案）は 9.3 / 10 章の照合層に任せる。
#
#   <種目名> <重量>/<回数>[/<セット数>] [<グループ> ...]     自重: <種目名>/<回数>[/<セット数>]
#
# 失敗時は推測補正せず、行番号と理由を返す（返信文の組み立ては 9.5）。
# ケース表は plan.md 9.1（A1〜A17 / R1〜R14）。
module RecordMessageParser
  # Group = 「セットグループ」
  #
  # 同じ重量・回数・セット数をひとまとまりとして扱うためのデータ。
  #
  # weight_kg = 「重量（kg）」
  #   例: 60kg → BigDecimal("60")
  #   自重の場合は nil。
  #
  # reps = 「回数」
  #   1セットあたりの反復回数。
  #   例: 60kgを5回 → reps: 5
  #
  # sets = 「セット数」
  #   同じ重量・回数を何セット行ったか。
  #   DB のカラムではなく、入力内容を一時的に保持するための値。
  #   例: 60kgを5回3セット → sets: 3

  # Entry = 「記録項目 / 1種目分の解析結果」
  #
  # LINEメッセージの1行を正常に解析できた場合の結果を保持する。
  #
  # line_number = 「行番号」
  #   LINEメッセージの何行目だったか。
  #
  # exercise_name = 「種目名」
  #   例: "ベンチプレス"
  #
  # groups = 「セットグループ群」
  #   Group オブジェクトの配列。
  #   重量や回数が途中で変わる場合は複数の Group を持つ。
  #
  # 例:
  #   ベンチ 60/5 70/3
  #
  #   groups = [
  #     Group.new(weight_kg: 60, reps: 5, sets: 1),
  #     Group.new(weight_kg: 70, reps: 3, sets: 1)
  #   ]
  #
  # Error = 「解析エラー」
  #
  # LINEメッセージの1行を正常に解析できなかった場合の情報を保持する。
  #
  # line_number = 「行番号」
  #   エラーになった入力が何行目だったか。
  #
  # line = 「元の入力行」
  #   実際にユーザーが入力した文字列。
  #
  # reason = 「エラー理由」
  #   例:
  #     :missing_group
  #     :invalid_group
  #     :weight_out_of_range
  #     :reps_out_of_range
  #     :sets_out_of_range
  #
  # Result = 「解析全体の結果」
  #
  # RecordMessageParser.call の最終結果を保持する。
  #
  # entries = 「正常に解析できた記録項目」
  #   Entry オブジェクトの配列。
  #
  # errors = 「解析エラー」
  #   Error オブジェクトの配列。
  #
  # success? = 「解析が成功したか」
  #   エラーが1件もなく、かつ正常な Entry が1件以上ある場合に true
  Group = Data.define(:weight_kg, :reps, :sets)               # weight_kg は BigDecimal または nil（自重）
  Entry = Data.define(:line_number, :exercise_name, :groups)
  Error = Data.define(:line_number, :line, :reason)
  Result = Data.define(:entries, :errors) do
    def success? = errors.empty? && entries.any?
  end

  # 入力可能な最大行数
  MAX_LINES = 20

  # 1セットあたりの最大回数
  MAX_REPS = 999

  # 1グループあたりの最大セット数
  MAX_SETS = 20

  # 重量の上限。
  # 1000kg以上は許可しないため、実際に許可される最大値は 999.9kg。
  MAX_WEIGHT_EXCLUSIVE = 1000

  # WEIGHT = 「重量の入力形式」
  #
  # 例:
  #   60
  #   60kg
  #   60キロ
  #   60キログラム
  #   62.5kg
  #
  # 単位は対応する位置に限り任意（大小文字不問）。
  # ㎏ と全角は NFKC で kg / 半角に畳まれている前提。
  WEIGHT = /\A(\d+(?:\.\d)?)(?:kg|キロ|キログラム)?\z/i

  # REPS = 「回数の入力形式」
  #
  # 例:
  #   5
  #   5回
  #   5rep
  #   5reps
  #   5レップ
  REPS = /\A(\d+)(?:回|reps?|レップ)?\z/i

  # SETS = 「セット数の入力形式」
  #
  # 例:
  #   3
  #   3セット
  #   3set
  #   3sets
  SETS = /\A(\d+)(?:セット|sets?)?\z/i

  module_function

  def call(text)
    lines = text.to_s.unicode_normalize(:nfkc).split(/\r?\n/)
    numbered = lines.each_with_index.filter_map { |line, i| [ i + 1, line.strip ] unless line.strip.empty? }

    return Result.new(entries: [], errors: [ Error.new(line_number: nil, line: nil, reason: :empty_message) ]) if numbered.empty?
    return Result.new(entries: [], errors: [ Error.new(line_number: nil, line: nil, reason: :too_many_lines) ]) if numbered.size > MAX_LINES

    entries = []
    errors = []
    numbered.each do |line_number, line|
      entry, reason = parse_line(line)
      if entry
        entries << Entry.new(line_number: line_number, exercise_name: entry[0], groups: entry[1])
      else
        errors << Error.new(line_number: line_number, line: line, reason: reason)
      end
    end

    # 1 行でも失敗したら全行不保存（SPEC 4.2.3）なので、成功した行も返さない
    Result.new(entries: errors.empty? ? entries : [], errors: errors)
  end

  # 1 行 → [[種目名, [Group, ...]], nil] または [nil, 理由]
  def parse_line(line)
    tokens = line.split(/[ \t]+/)
    first_group_index = tokens.index { |t| t.include?("/") }
    return [ nil, :missing_group ] unless first_group_index

    name_tokens = tokens[0...first_group_index]
    name_part, group_part = split_name_and_group(tokens[first_group_index])
    return [ nil, :invalid_group ] unless group_part

    name_tokens << name_part unless name_part.empty?
    exercise_name = name_tokens.join(" ")
    return [ nil, :missing_exercise_name ] if exercise_name.empty?

    groups = []
    [ group_part, *tokens[(first_group_index + 1)..] ].each do |token|
      group, reason = parse_group(token)
      return [ nil, reason ] unless group

      groups << group
    end
    [ [ exercise_name, groups ], nil ]
  end

  # 直前にあると「数値の続き」とみなす文字（数字・小数点・カンマ・符号）。`62,5/5` を「62,」＋「5/5」、
  # `-5/5` を「-」＋「5/5」と切らないため（R8 の形式エラーとして parse_group で拒否させる）
  NUMBER_ADJACENT = /[\d.,+\-]/

  # 「種目名と数値の間のスペースは任意」: トークン内で「数値または / の直前が数値の一部でない位置」
  # のうち、そこから先がグループとして読める最初の位置で切る。種目名が数字で終わる場合はスペースが必要
  # （`ベンチ260/5` は「ベンチ 260kg」）。"45度レッグプレス100/12" は "45" から先がグループにならないので
  # "100/12" で切れる
  def split_name_and_group(token)
    token.each_char.with_index do |char, i|
      next unless char.match?(%r{[\d/]})
      next if i.positive? && token[i - 1].match?(NUMBER_ADJACENT)
      next unless group_like?(token[i..])

      return [ token[0...i], token[i..] ]
    end
    nil
  end

  # 先頭がグループの形（[数値[単位]]/...）に見えるか。単位候補は文字列一般（未知の単位はここでは
  # 弾かず parse_group で拒否する）
  def group_like?(str)
    str.match?(%r{\A(?:\d+(?:\.\d+)?[^\s/\d]*)?/})
  end

  # "60kg/5回/3セット" → Group。形・単位の位置・数値の形式は :invalid_group、範囲は *_out_of_range
  def parse_group(token)
    parts = token.split("/", -1)
    return [ nil, :invalid_group ] unless parts.size.between?(2, 3)

    weight_str, reps_str, sets_str = parts
    weight_match = weight_str.empty? ? nil : WEIGHT.match(weight_str)
    return [ nil, :invalid_group ] if !weight_str.empty? && weight_match.nil?
    reps_match = REPS.match(reps_str)
    return [ nil, :invalid_group ] unless reps_match
    sets_match = sets_str.nil? ? nil : SETS.match(sets_str)
    return [ nil, :invalid_group ] if !sets_str.nil? && sets_match.nil?

    weight = weight_match && BigDecimal(weight_match[1])
    return [ nil, :weight_out_of_range ] if weight && weight >= MAX_WEIGHT_EXCLUSIVE
    weight = nil if weight&.zero? # 0kg は自重として扱う（SPEC 4.2.2）

    reps = reps_match[1].to_i
    return [ nil, :reps_out_of_range ] unless reps.between?(1, MAX_REPS)

    sets = sets_match ? sets_match[1].to_i : 1
    return [ nil, :sets_out_of_range ] unless sets.between?(1, MAX_SETS)

    [ Group.new(weight_kg: weight, reps: reps, sets: sets), nil ]
  end

  private_class_method :parse_line, :split_name_and_group, :group_like?, :parse_group
end
