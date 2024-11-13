class CreateGitlabUsers < ActiveRecord::Migration[8.0]
  def change
    create_table :gitlab_users do |t|
      t.text :username, null: false, limit: 256

      t.timestamps null: false

      t.index :username, unique: true
    end
  end
end
