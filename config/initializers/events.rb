ActiveSupport::Notifications.subscribe "gitlab.client.query" do |*args|
  Honeybadger.notify "Executing GraphQL query"
  Rails.logger.debug "Executing GraphQL query"
end
