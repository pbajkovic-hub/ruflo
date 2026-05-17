-- Paja Training — SQLite schema v1 (GRDB migration "v1")
-- On-device only. Personal use: a single seeded users row, but user_id is on
-- every table so this can grow into a product without a rewrite.
-- Dates/times are ISO-8601 TEXT. Booleans are INTEGER 0/1. JSON is TEXT.
PRAGMA foreign_keys = ON;

CREATE TABLE users (
  id            TEXT PRIMARY KEY,                 -- UUID
  display_name  TEXT NOT NULL,
  timezone      TEXT NOT NULL DEFAULT 'UTC',      -- IANA tz; owns the day boundary
  created_at    TEXT NOT NULL
);

-- ---- Integrations -------------------------------------------------------
-- The Oura Personal Access Token is stored in the iOS Keychain, NOT here.
-- This row only records that a connection exists + its status.
CREATE TABLE connections (
  id            TEXT PRIMARY KEY,
  user_id       TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  provider      TEXT NOT NULL CHECK (provider IN ('oura','apple_health')),
  status        TEXT NOT NULL DEFAULT 'connected'
                CHECK (status IN ('connected','token_invalid','membership_lapsed','disconnected')),
  keychain_ref  TEXT,                             -- Keychain account key for the token
  last_sync_at  TEXT,
  UNIQUE (user_id, provider)
);

-- ---- Exercise library + programs ---------------------------------------
CREATE TABLE exercises (
  id            TEXT PRIMARY KEY,
  user_id       TEXT REFERENCES users(id) ON DELETE CASCADE,  -- NULL = built-in
  name          TEXT NOT NULL,
  category      TEXT CHECK (category IN ('push','pull','legs','upper','lower','core','accessory')),
  is_main_lift  INTEGER NOT NULL DEFAULT 0,
  UNIQUE (user_id, name)
);
-- UNIQUE(user_id,name) does NOT dedupe built-ins: NULL user_id never collides
-- in a SQLite UNIQUE. Enforce unique built-in exercise names explicitly.
CREATE UNIQUE INDEX ux_exercises_builtin_name
  ON exercises(name) WHERE user_id IS NULL;

-- A program is a split type the owner follows. Template days are defined in
-- code (Engine/Programs) and referenced by key for stability.
CREATE TABLE program (
  id            TEXT PRIMARY KEY,
  user_id       TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  split         TEXT NOT NULL CHECK (split IN ('ppl','upper_lower')),
  template_key  TEXT NOT NULL,                    -- e.g. 'ppl.v1', 'ul.v1'
  created_at    TEXT NOT NULL
);

-- An active run of a program: where in the rotation + the deload counter.
CREATE TABLE program_instance (
  id              TEXT PRIMARY KEY,
  user_id         TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  program_id      TEXT NOT NULL REFERENCES program(id) ON DELETE CASCADE,
  status          TEXT NOT NULL DEFAULT 'active'
                  CHECK (status IN ('active','paused','completed')),
  rotation_index  INTEGER NOT NULL DEFAULT 0,     -- which day of the split is next
  week_in_block   INTEGER NOT NULL DEFAULT 1,     -- for deload cadence
  started_at      TEXT NOT NULL
);

-- Per-(user,exercise) working numbers the engine progresses.
CREATE TABLE lift_progress (
  id            TEXT PRIMARY KEY,
  user_id       TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  exercise_id   TEXT NOT NULL REFERENCES exercises(id) ON DELETE CASCADE,
  working_kg    REAL NOT NULL,
  target_reps   INTEGER NOT NULL,
  last_outcome  TEXT CHECK (last_outcome IN ('hit','missed','skipped')),
  updated_at    TEXT NOT NULL,
  UNIQUE (user_id, exercise_id)
);

-- ---- Training log ------------------------------------------------------
CREATE TABLE sessions (
  id                  TEXT PRIMARY KEY,
  user_id             TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  program_instance_id TEXT REFERENCES program_instance(id) ON DELETE SET NULL,
  session_date        TEXT NOT NULL,              -- local calendar day
  day_label           TEXT,                       -- 'Push' / 'Upper' / 'Recovery'
  status              TEXT NOT NULL DEFAULT 'planned'
                      CHECK (status IN ('planned','in_progress','completed','skipped')),
  recovery_state      TEXT CHECK (recovery_state IN ('green','amber','red','calibrating','unknown')),
  recovery_pct        INTEGER,                    -- nullable; null during calibrating/no-data
  prescription_why    TEXT,                       -- the one-line explanation shown to user
  deleted_at          TEXT,                       -- soft delete (history is irreplaceable)
  created_at          TEXT NOT NULL
);
CREATE INDEX ix_sessions_user_date ON sessions(user_id, session_date);

CREATE TABLE session_exercises (
  id            TEXT PRIMARY KEY,
  session_id    TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
  exercise_id   TEXT NOT NULL REFERENCES exercises(id),
  order_index   INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE sets (
  id                  TEXT PRIMARY KEY,
  session_exercise_id TEXT NOT NULL REFERENCES session_exercises(id) ON DELETE CASCADE,
  set_number          INTEGER NOT NULL,
  target_reps         INTEGER,
  target_kg           REAL,
  done_reps           INTEGER,
  done_kg             REAL,
  rpe                 REAL,
  is_warmup           INTEGER NOT NULL DEFAULT 0,
  is_backoff          INTEGER NOT NULL DEFAULT 0,
  completed           INTEGER NOT NULL DEFAULT 0
);

-- ---- Goals + weekly rollup --------------------------------------------
CREATE TABLE goals (
  id            TEXT PRIMARY KEY,
  user_id       TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  title         TEXT NOT NULL,
  metric        TEXT NOT NULL,                    -- e.g. 'squat_1rm'
  unit          TEXT NOT NULL,
  target_value  REAL NOT NULL,
  target_date   TEXT,
  status        TEXT NOT NULL DEFAULT 'active'
                CHECK (status IN ('active','achieved','paused','abandoned')),
  created_at    TEXT NOT NULL
);

CREATE TABLE goal_progress (
  id            TEXT PRIMARY KEY,
  goal_id       TEXT NOT NULL REFERENCES goals(id) ON DELETE CASCADE,
  recorded_at   TEXT NOT NULL,
  value         REAL NOT NULL,
  source        TEXT NOT NULL DEFAULT 'session'
);

CREATE TABLE weekly_logs (
  id                TEXT PRIMARY KEY,
  user_id           TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  week_start_date   TEXT NOT NULL,                -- Monday, local
  sessions_done     INTEGER,
  total_volume_kg   REAL,
  avg_recovery_pct  REAL,
  notes             TEXT,
  UNIQUE (user_id, week_start_date)
);

-- ---- Wearable ingestion ------------------------------------------------
-- Raw, one row per user/day/source. Never overwritten across sources.
CREATE TABLE daily_logs (
  id                  TEXT PRIMARY KEY,
  user_id             TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  log_date            TEXT NOT NULL,
  source              TEXT NOT NULL CHECK (source IN ('oura','apple_health')),
  source_record_id    TEXT,                       -- Oura document id for revision-aware upsert
  source_updated_at   TEXT,                       -- revision marker (last-write-wins)
  readiness_score     INTEGER,                    -- Oura daily_readiness.score (nullable)
  sleep_score         INTEGER,                    -- Oura daily_sleep.score (the ONE canonical one)
  sleep_total_min     INTEGER,
  hrv_ms              REAL,
  resting_hr          INTEGER,
  temp_deviation      REAL,
  steps               INTEGER,
  active_kcal         INTEGER,
  workout_min         INTEGER,
  raw_payload         TEXT,                       -- full source JSON, never discarded
  synced_at           TEXT NOT NULL,
  UNIQUE (user_id, log_date, source)
);

-- Deterministic, rebuildable per-metric merge of all sources for a day.
-- Precedence: Oura wins sleep/HRV/readiness; Apple Watch wins workout/active;
-- most-data-wins when one source is missing that day.
CREATE TABLE resolved_daily_metrics (
  user_id           TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  log_date          TEXT NOT NULL,
  recovery_pct      INTEGER,                      -- null = no basis (calibrating/no data)
  recovery_state    TEXT CHECK (recovery_state IN ('green','amber','red','calibrating','unknown')),
  confidence        TEXT NOT NULL DEFAULT 'high'
                    CHECK (confidence IN ('high','low','none')),
  sleep_score       INTEGER,
  sleep_total_min   INTEGER,
  hrv_ms            REAL,
  resting_hr        INTEGER,
  workout_min       INTEGER,
  recovery_source   TEXT,                         -- which source supplied recovery
  rebuilt_at        TEXT NOT NULL,
  PRIMARY KEY (user_id, log_date)
);

-- ---- Weekly body composition (InBody) — NOT daily ----------------------
CREATE TABLE body_composition (
  id                      TEXT PRIMARY KEY,
  user_id                 TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  measured_on             TEXT NOT NULL,          -- date of the InBody scan
  source                  TEXT NOT NULL DEFAULT 'inbody_manual'
                          CHECK (source IN ('inbody_manual','inbody_csv','apple_health','manual')),
  weight_kg               REAL,
  body_fat_pct            REAL,
  skeletal_muscle_mass_kg REAL,
  lean_body_mass_kg       REAL,
  total_body_water_l      REAL,
  visceral_fat_level      REAL,
  bmr_kcal                INTEGER,
  bmi                     REAL,
  inbody_score            INTEGER,
  segmental_lean_json     TEXT,
  raw_payload             TEXT,
  notes                   TEXT,
  created_at              TEXT NOT NULL,
  UNIQUE (user_id, measured_on, source)
);

CREATE TABLE schema_version (version INTEGER NOT NULL);
INSERT INTO schema_version (version) VALUES (1);
