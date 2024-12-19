Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html
  resources :web_push_subscriptions, only: :create
  mount MissionControl::Jobs::Engine, at: "/jobs"

  get "/mrs", to: "merge_requests#index", as: :merge_requests
  get "/mrs/list", to: "merge_requests#list", as: :merge_requests_list

  get "/api/graph/monthly_merged_mrs",
    to: "api/user_merge_request_charts#monthly_merged_merge_request_stats",
    as: :monthly_merged_merge_request_stats, defaults: {format: :json}

  get "/admin/dashboard", to: "admin/dashboard#index", as: :admin_dashboard

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", :as => :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  get "manifest" => "rails/pwa#manifest", :as => :pwa_manifest
  get "service-worker" => "rails/pwa#service_worker", :as => :pwa_service_worker

  # Defines the root path route ("/")
  root "merge_requests#index"
end
