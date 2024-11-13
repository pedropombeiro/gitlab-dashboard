class AddContactedAtColumnToGitlabUsersTable < ActiveRecord::Migration[8.0]
  def change
    add_column :gitlab_users, :contacted_at, :datetime
  end
end
