require "rails_helper"

# 8.8 連携コード方式の廃止（SPEC 版 3.0）: 旧画面 6「LINE 連携設定」のルートが残っていないこと
RSpec.describe "旧 /settings/line ルート", type: :routing do
  it "GET /settings/line はルーティングされない" do
    expect(get: "/settings/line").not_to be_routable
  end

  it "POST /settings/line/link_code はルーティングされない" do
    expect(post: "/settings/line/link_code").not_to be_routable
  end

  it "DELETE /settings/line はルーティングされない" do
    expect(delete: "/settings/line").not_to be_routable
  end
end
