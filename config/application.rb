require_relative "boot"

require "rails"
# Pick the frameworks you want:
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "active_storage/engine"
require "action_controller/railtie"
require "action_mailer/railtie"
require "action_mailbox/engine"
require "action_text/engine"
require "action_view/railtie"
require "action_cable/engine"
# require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module WorkoutTracker
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # 記録日は受信日（JST）で決める（SPEC 4.2.2）。Web の「今日」もこれに揃える。
    # 当面は日本国内向けのため JST 固定（2026-09-24 決定・SPEC 10 章 #18）。日本以外へ展開して
    # 「今日」の基準がユーザーごとに変わる時は、この設定ではなく users.time_zone 等へ移行する
    # （DB の datetime は UTC 保存のまま）
    config.time_zone = "Tokyo"
    # config.eager_load_paths << Rails.root.join("extras")

    # Don't generate system test files.
    config.generators.system_tests = nil

    # 画面のメッセージは日本語で表示する（plan.md 5.5）
    config.i18n.default_locale = :ja
  end
end
