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

ActiveRecord::Schema[8.1].define(version: 2026_10_22_090000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pg_trgm"

  create_table "exercise_aliases", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "exercise_id", null: false
    t.string "alias", null: false
    t.string "normalized_alias", null: false
    t.boolean "confirmed", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["exercise_id"], name: "index_exercise_aliases_on_exercise_id"
    t.index ["user_id", "normalized_alias"], name: "index_exercise_aliases_on_user_id_and_normalized_alias", unique: true
  end

  create_table "exercises", force: :cascade do |t|
    t.bigint "user_id"
    t.string "name", null: false
    t.string "normalized_name", null: false
    t.string "category"
    t.boolean "bodyweight", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id", "normalized_name"], name: "index_exercises_on_user_id_and_normalized_name", unique: true, nulls_not_distinct: true
  end

  create_table "pending_workout_entries", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.text "source_text", null: false
    t.jsonb "parsed_lines", null: false
    t.datetime "expires_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_pending_workout_entries_on_user_id", unique: true
  end

  create_table "processed_line_events", force: :cascade do |t|
    t.string "webhook_event_id", null: false
    t.datetime "received_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["webhook_event_id"], name: "index_processed_line_events_on_webhook_event_id", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.string "name", null: false
    t.datetime "remember_created_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "line_user_id", null: false
    t.boolean "line_blocked", default: false, null: false
    t.index ["line_user_id"], name: "index_users_on_line_user_id", unique: true
  end

  create_table "workout_sets", force: :cascade do |t|
    t.bigint "workout_id", null: false
    t.bigint "exercise_id", null: false
    t.decimal "weight_kg", precision: 5, scale: 1
    t.integer "reps", null: false
    t.integer "set_number", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["exercise_id"], name: "index_workout_sets_on_exercise_id"
    t.index ["workout_id", "exercise_id", "set_number"], name: "index_workout_sets_on_workout_and_exercise_and_set_number", unique: true
    t.check_constraint "reps > 0", name: "workout_sets_reps_positive"
    t.check_constraint "set_number > 0", name: "workout_sets_set_number_positive"
    t.check_constraint "weight_kg < 1000::numeric", name: "workout_sets_weight_kg_upper_bound"
    t.check_constraint "weight_kg >= 0::numeric", name: "workout_sets_weight_kg_non_negative"
  end

  create_table "workouts", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.date "performed_on", null: false
    t.text "note"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id", "performed_on"], name: "index_workouts_on_user_id_and_performed_on", unique: true
  end

  add_foreign_key "exercise_aliases", "exercises"
  add_foreign_key "exercise_aliases", "users"
  add_foreign_key "exercises", "users"
  add_foreign_key "pending_workout_entries", "users"
  add_foreign_key "workout_sets", "exercises"
  add_foreign_key "workout_sets", "workouts"
  add_foreign_key "workouts", "users"
end
