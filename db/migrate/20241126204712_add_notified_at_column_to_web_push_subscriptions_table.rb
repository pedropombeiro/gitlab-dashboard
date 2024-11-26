class AddNotifiedAtColumnToWebPushSubscriptionsTable < ActiveRecord::Migration[8.0]
  def change
    add_column :web_push_subscriptions, :notified_at, :datetime
  end
end
