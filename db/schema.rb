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

ActiveRecord::Schema[8.1].define(version: 2026_09_01_055350) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "exercises", force: :cascade do |t|
    t.boolean "bodyweight", default: false, null: false
    t.string "category"
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.string "normalized_name", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.index ["user_id", "normalized_name"], name: "index_exercises_on_user_id_and_normalized_name", unique: true, nulls_not_distinct: true
  end

  create_table "processed_line_events", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "received_at", null: false
    t.datetime "updated_at", null: false
    t.string "webhook_event_id", null: false
    t.index ["webhook_event_id"], name: "index_processed_line_events_on_webhook_event_id", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.boolean "line_blocked", default: false, null: false
    t.string "line_link_code"
    t.datetime "line_link_code_expires_at"
    t.string "line_user_id"
    t.string "name", null: false
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["line_link_code"], name: "index_users_on_line_link_code", unique: true
    t.index ["line_user_id"], name: "index_users_on_line_user_id", unique: true, where: "(line_user_id IS NOT NULL)"
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  create_table "workout_sets", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "exercise_id", null: false
    t.integer "reps", null: false
    t.integer "set_number", null: false
    t.datetime "updated_at", null: false
    t.decimal "weight_kg", precision: 5, scale: 1
    t.bigint "workout_id", null: false
    t.index ["exercise_id"], name: "index_workout_sets_on_exercise_id"
    t.index ["workout_id", "exercise_id", "set_number"], name: "index_workout_sets_on_workout_and_exercise_and_set_number", unique: true
    t.check_constraint "reps > 0", name: "workout_sets_reps_positive"
    t.check_constraint "set_number > 0", name: "workout_sets_set_number_positive"
    t.check_constraint "weight_kg < 1000::numeric", name: "workout_sets_weight_kg_upper_bound"
    t.check_constraint "weight_kg >= 0::numeric", name: "workout_sets_weight_kg_non_negative"
  end

  create_table "workouts", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "note"
    t.date "performed_on", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id", "performed_on"], name: "index_workouts_on_user_id_and_performed_on", unique: true
  end

  add_foreign_key "exercises", "users"
  add_foreign_key "workout_sets", "exercises"
  add_foreign_key "workout_sets", "workouts"
  add_foreign_key "workouts", "users"
end
