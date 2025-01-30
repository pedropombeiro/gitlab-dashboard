if Rails.env.production? && ENV["PROMETHEUS_EXPORTER_HOST"].present?
  require "prometheus_exporter/middleware"

  # This reports stats per request like HTTP status and timings
  Rails.application.middleware.unshift PrometheusExporter::Middleware
end
