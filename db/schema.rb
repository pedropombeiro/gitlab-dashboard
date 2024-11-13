# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.0].define(version: 2024_11_13_170325) do
  create_table "gitlab_users", force: :cascade do |t|
    t.string "username", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "contacted_at"
    t.index ["username"], name: "index_gitlab_users_on_username", unique: true
  end

  create_table "web_push_subscriptions", force: :cascade do |t|
    t.integer "gitlab_user_id", null: false
    t.text "endpoint", null: false
    t.text "auth_key", null: false
    t.text "p256dh_key", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "user_agent"
    t.index ["gitlab_user_id"], name: "index_web_push_subscriptions_on_gitlab_user_id"
  end

  add_foreign_key "web_push_subscriptions", "gitlab_users"
end
