class CreateGitlabUsers < ActiveRecord::Migration[8.0]
  def change
    create_table :gitlab_users do |t|
      t.string :username, null: false

      t.timestamps null: false

      t.index :username, unique: true
    end
  end
end
