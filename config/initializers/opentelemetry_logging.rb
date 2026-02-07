# frozen_string_literal: true

require "json"

# OpenTelemetry Log Correlation
#
# Configures Rails logging to include trace context (trace_id, span_id)
# in log entries, enabling correlation between logs and distributed traces in Grafana.

module OpenTelemetry
  module Logging
    # Base formatter with shared trace context extraction
    class BaseFormatter < ::Logger::Formatter
      private

      def trace_context
        return {} unless defined?(::OpenTelemetry::Trace)

        span_context = ::OpenTelemetry::Trace.current_span.context
        return {} unless span_context.valid?

        {
          trace_id: span_context.hex_trace_id,
          span_id: span_context.hex_span_id,
          trace_flags: span_context.trace_flags.sampled? ? "01" : "00"
        }
      end

      def format_message(msg)
        case msg
        when ::String then msg
        when ::Exception then format_exception(msg)
        else msg.inspect
        end
      end

      def format_exception(exception)
        parts = ["#{exception.message} (#{exception.class})"]
        parts << exception.backtrace.join("\n") if exception.backtrace&.any?
        parts.join("\n")
      end

      def service_name
        ENV.fetch("OTEL_SERVICE_NAME", "gitlab-dashboard")
      end
    end

    # Human-readable formatter with trace context and TaggedLogging support
    # Format: [timestamp] [severity] [trace_id=xxx span_id=xxx] [tags] message
    class TextFormatter < BaseFormatter
      # Support for ActiveSupport::TaggedLogging
      attr_accessor :current_tags

      def initialize
        super
        @current_tags = []
      end

      def call(severity, timestamp, _progname, msg)
        ctx = trace_context
        trace_str = ctx.empty? ? "" : " [trace_id=#{ctx[:trace_id]} span_id=#{ctx[:span_id]}]"
        tags_str = current_tags.any? ? " [#{current_tags.join("] [")}]" : ""

        "[#{timestamp.utc.iso8601(3)}] [#{severity}]#{trace_str}#{tags_str} #{format_message(msg)}\n"
      end

      # Required by ActiveSupport::TaggedLogging
      def tagged(*tags)
        new_tags = tags.flatten.compact
        old_tags = current_tags
        self.current_tags = old_tags + new_tags
        yield self
      ensure
        self.current_tags = old_tags
      end

      def push_tags(*tags)
        tags = tags.flatten.compact
        current_tags.concat(tags)
        tags
      end

      def pop_tags(count = 1)
        current_tags.pop(count)
      end

      def clear_tags!
        current_tags.clear
      end
    end

    # Structured JSON formatter for log aggregation systems (Loki, etc.)
    class JsonFormatter < BaseFormatter
      # Support for ActiveSupport::TaggedLogging
      attr_accessor :current_tags

      def initialize
        super
        @current_tags = []
      end

      def call(severity, timestamp, _progname, msg)
        entry = {
          timestamp: timestamp.utc.iso8601(3),
          level: severity,
          message: format_message(msg),
          service: service_name,
          environment: Rails.env
        }.merge(trace_context)

        entry[:tags] = current_tags if current_tags.any?

        "#{entry.to_json}\n"
      end

      # Required by ActiveSupport::TaggedLogging
      def tagged(*tags)
        new_tags = tags.flatten.compact
        old_tags = current_tags
        self.current_tags = old_tags + new_tags
        yield self
      ensure
        self.current_tags = old_tags
      end

      def push_tags(*tags)
        tags = tags.flatten.compact
        current_tags.concat(tags)
        tags
      end

      def pop_tags(count = 1)
        current_tags.pop(count)
      end

      def clear_tags!
        current_tags.clear
      end
    end
  end
end

# Configure the logger formatter when OpenTelemetry is enabled
Rails.application.config.after_initialize do
  next if ENV["OTEL_EXPORTER_OTLP_ENDPOINT"].blank?

  formatter = if ENV["OTEL_LOGS_FORMAT"] == "json"
    OpenTelemetry::Logging::JsonFormatter.new
  else
    OpenTelemetry::Logging::TextFormatter.new
  end

  # Handle BroadcastLogger (Rails 7.1+) or regular logger
  logger = Rails.logger
  if logger.respond_to?(:broadcasts)
    logger.broadcasts.each do |broadcast|
      broadcast.formatter = formatter if broadcast.respond_to?(:formatter=)
    end
  elsif logger.respond_to?(:formatter=)
    logger.formatter = formatter
  end

  Rails.logger.info "OpenTelemetry log correlation enabled (#{formatter.class.name.demodulize})"
end
