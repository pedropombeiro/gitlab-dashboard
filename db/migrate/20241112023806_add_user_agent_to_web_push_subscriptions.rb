class AddUserAgentToWebPushSubscriptions < ActiveRecord::Migration[8.0]
  def change
    add_column :web_push_subscriptions, :user_agent, :text
  end
end
