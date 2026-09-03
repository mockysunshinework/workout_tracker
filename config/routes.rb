Rails.application.routes.draw do
  devise_for :users
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  # NOTE: minimal landing for 2.3; replaced by the real dashboard in 6.3
  root "home#index"

  resources :workouts, only: [ :index, :show ] do
    resources :workout_sets, only: [ :create, :update, :destroy ]
  end
  resources :exercises, only: [ :index, :create, :update, :destroy ]

  # LINE 連携設定（SPEC 4.4 画面 6）: 表示 / 解除 / コード発行
  namespace :settings do
    resource :line, only: [ :show, :destroy ], controller: "line" do
      post :link_code
    end
  end

  # LINE プラットフォームからの Webhook 受信（SPEC 4.2.4 / 8 章）
  post "webhooks/line", to: "line_webhooks#create", as: :webhooks_line

  # ダッシュボード（6.3）のグラフが参照する JSON エンドポイント（SPEC 4.4）
  get "charts/exercise_progress", to: "charts#exercise_progress", as: :charts_exercise_progress
  get "charts/training_frequency", to: "charts#training_frequency", as: :charts_training_frequency
end
