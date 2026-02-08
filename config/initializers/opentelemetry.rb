# frozen_string_literal: true

return if ENV["OTEL_EXPORTER_OTLP_ENDPOINT"].blank?

require "opentelemetry/sdk"
require "opentelemetry/exporter/otlp"

# Configure OpenTelemetry SDK
OpenTelemetry::SDK.configure do |c|
  # Service name (defaults to OTEL_SERVICE_NAME env var or "gitlab-dashboard")
  c.service_name = ENV.fetch("OTEL_SERVICE_NAME", "gitlab-dashboard")

  # Service version from git revision file (set during Docker build)
  revision_file = Rails.root.join("REVISION")
  service_version = if revision_file.exist?
    revision_file.read.strip.presence || "unknown"
  else
    "development"
  end
  c.service_version = service_version

  # Resource attributes (all values must be strings, integers, floats, or booleans)
  c.resource = OpenTelemetry::SDK::Resources::Resource.create(
    "deployment.environment" => Rails.env.to_s,
    "service.namespace" => "gitlab-dashboard",
    "service.version" => service_version
  )

  # Use all available instrumentations with specific configurations
  c.use_all(
    "OpenTelemetry::Instrumentation::ActiveRecord" => {
      # Don't include full SQL in spans (security)
      db_statement: :obfuscate
    },
    "OpenTelemetry::Instrumentation::Rack" => {},
    "OpenTelemetry::Instrumentation::Faraday" => {},
    "OpenTelemetry::Instrumentation::Net::HTTP" => {}
  )
end

Rails.logger.info "OpenTelemetry initialized with OTLP exporter to #{ENV["OTEL_EXPORTER_OTLP_ENDPOINT"]}"
