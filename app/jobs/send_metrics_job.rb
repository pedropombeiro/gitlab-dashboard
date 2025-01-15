class SendMetricsJob < ApplicationJob
  include Honeybadger::InstrumentationHelper

  self.queue_adapter = :solid_queue
  limits_concurrency to: 1, key: ->(*_args) {}
  queue_as :default

  def perform(*_args)
    metric_source "custom_metrics"

    gauge("user_count", -> { ::GitlabUser.count })
    gauge("users_with_push_subscriptions", -> { ::WebPushSubscription.select(:gitlab_user_id).distinct.count })
    gauge("active_dashboard_count", -> { ::GitlabUser.active.count })
  end
end
