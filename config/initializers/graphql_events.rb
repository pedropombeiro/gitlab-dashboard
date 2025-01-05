class GraphQLQueryEventPublisher
  include Honeybadger::InstrumentationHelper

  def publish(event)
    name = event.payload[:operation_name].delete_prefix("#{self.class.name}__").delete_suffix("Query").underscore

    metric_source "graphql_metrics"
    metric_attributes(name: name, **event.payload[:variables].slice("username"))

    increment_counter "graphql.query.count"
    histogram "graphql.query.duration", duration: (event.duration / 1000).seconds
  end
end

graphql_event_publisher = GraphQLQueryEventPublisher.new

ActiveSupport::Notifications.subscribe "query.graphql" do |event|
  graphql_event_publisher.publish(event)
end
