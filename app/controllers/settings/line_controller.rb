module Settings
  class LineController < ApplicationController
    def show
    end

    def link_code
      current_user.issue_line_link_code!
      redirect_to settings_line_path, notice: "連携コードを発行しました"
    end

    def destroy
      current_user.unlink_line!
      redirect_to settings_line_path, notice: "LINE 連携を解除しました"
    end
  end
end
