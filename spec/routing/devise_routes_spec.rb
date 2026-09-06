require "rails_helper"

# 8.7 メール＋パスワード認証の廃止（SPEC 版 3.0）: 会員登録・パスワード再設定・パスワードログインのルートが無いこと
RSpec.describe "廃止した Devise ルート", type: :routing do
  it "会員登録（GET /users/sign_up）はルーティングされない" do
    expect(get: "/users/sign_up").not_to be_routable
  end

  it "パスワード再設定（GET /users/password/new）はルーティングされない" do
    expect(get: "/users/password/new").not_to be_routable
  end

  it "パスワードログイン（POST /users/sign_in）はルーティングされない" do
    expect(post: "/users/sign_in").not_to be_routable
  end
end
