class EnablePgTrgm < ActiveRecord::Migration[8.1]
  # 種目候補検索の類似度段階（SPEC 4.3.1(2)・10.1 で採用決定）。trusted extension のため DB 所有者で有効化できる。
  # trigram index は作らない（対象はユーザーごとにプリセット 22 件＋独自種目の数十行で、全件を similarity() で評価して足りる）。
  def change
    enable_extension "pg_trgm"
  end
end
