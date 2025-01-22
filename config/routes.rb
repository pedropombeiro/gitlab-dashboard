Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html
  mount MissionControl::Jobs::Engine, at: "/jobs"

  get "/reviewers", to: "reviewers#index", as: :reviewers
  get "/reviewers/list", to: "reviewers#list", as: :reviewers_list

  get "/mrs", to: "merge_requests#index", as: :merge_requests
  get "/mrs/open_list", to: "merge_requests#open_list", as: :open_merge_requests_list
  get "/mrs/merged_list", to: "merge_requests#merged_list", as: :merged_merge_requests_list
  get "/mrs/merged_chart", to: "merge_requests#merged_chart", as: :merged_merge_requests_chart

  get "/mrs/list", to: redirect("/mrs/open_list")
  get "/mrs/:author", to: "merge_requests#legacy_index"

  get "/api/graph/monthly_merged_mrs",
    to: "api/user_merge_request_charts#monthly_merged_merge_request_stats",
    as: :monthly_merged_merge_request_stats, defaults: {format: :json}

  post "/api/web_push_subscriptions", to: "api/web_push_subscriptions#create", as: :web_push_subscriptions

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
