class CreateWebPushSubscriptions < ActiveRecord::Migration[8.0]
  def change
    create_table :web_push_subscriptions do |t|
      t.references :gitlab_user, null: false, foreign_key: true
      t.text :endpoint, null: false
      t.text :auth_key, null: false
      t.text :p256dh_key, null: false

      t.timestamps null: false
    end
  end
end
