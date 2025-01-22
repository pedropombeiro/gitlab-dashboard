class GraphQLQueryEventPublisher
  include Honeybadger::InstrumentationHelper

  def publish(event)
    name = event.payload[:operation_name].delete_prefix("GitlabClient__").delete_suffix("Query").underscore

    metric_source "graphql_metrics"
    metric_attributes(name: name, **event.payload[:variables].slice("username", "fullPath"))

    increment_counter "graphql.query.count"
    histogram "graphql.query.duration", duration: event.duration
  end
end

graphql_event_publisher = GraphQLQueryEventPublisher.new

ActiveSupport::Notifications.monotonic_subscribe "query.graphql" do |event|
  graphql_event_publisher.publish(event)
end
