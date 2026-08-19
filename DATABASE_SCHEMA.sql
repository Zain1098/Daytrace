-- DayTrace canonical logical schema v1
-- Implement with Drift typed tables and versioned migrations.
-- Timestamp convention: UTC epoch milliseconds (INTEGER).
-- UUIDs are generated locally and stored as TEXT.

PRAGMA foreign_keys = ON;

CREATE TABLE categories (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  icon_key TEXT,
  color_value INTEGER,
  sort_order INTEGER NOT NULL DEFAULT 0,
  is_system INTEGER NOT NULL DEFAULT 0 CHECK (is_system IN (0,1)),
  is_archived INTEGER NOT NULL DEFAULT 0 CHECK (is_archived IN (0,1)),
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  deleted_at INTEGER
);
CREATE UNIQUE INDEX idx_categories_name_active ON categories(name) WHERE deleted_at IS NULL;

CREATE TABLE tasks (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL CHECK (length(trim(title)) > 0),
  description TEXT,
  category_id TEXT REFERENCES categories(id) ON DELETE SET NULL,
  status TEXT NOT NULL DEFAULT 'planned' CHECK (status IN ('planned','in_progress','paused','completed','cancelled','archived')),
  priority TEXT NOT NULL DEFAULT 'medium' CHECK (priority IN ('low','medium','high','urgent')),
  planned_at INTEGER,
  due_at INTEGER,
  estimated_minutes INTEGER CHECK (estimated_minutes IS NULL OR estimated_minutes >= 0),
  completed_at INTEGER,
  cancelled_at INTEGER,
  recurrence_rule_id TEXT,
  parent_template_task_id TEXT,
  notes TEXT,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  deleted_at INTEGER
);
CREATE INDEX idx_tasks_status_due ON tasks(status, due_at);
CREATE INDEX idx_tasks_planned_at ON tasks(planned_at);
CREATE INDEX idx_tasks_category ON tasks(category_id);

CREATE TABLE subtasks (
  id TEXT PRIMARY KEY,
  task_id TEXT NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  is_completed INTEGER NOT NULL DEFAULT 0 CHECK (is_completed IN (0,1)),
  sort_order INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);
CREATE INDEX idx_subtasks_task ON subtasks(task_id, sort_order);

CREATE TABLE recurrence_rules (
  id TEXT PRIMARY KEY,
  frequency TEXT NOT NULL CHECK (frequency IN ('daily','weekly','monthly')),
  interval_value INTEGER NOT NULL DEFAULT 1 CHECK (interval_value > 0),
  weekdays_mask INTEGER,
  day_of_month INTEGER CHECK (day_of_month IS NULL OR day_of_month BETWEEN 1 AND 31),
  starts_at INTEGER NOT NULL,
  ends_at INTEGER,
  occurrence_count INTEGER,
  timezone_name TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);

CREATE TABLE time_entries (
  id TEXT PRIMARY KEY,
  task_id TEXT REFERENCES tasks(id) ON DELETE SET NULL,
  category_id TEXT REFERENCES categories(id) ON DELETE SET NULL,
  entry_type TEXT NOT NULL DEFAULT 'task' CHECK (entry_type IN ('task','break','meeting','untracked','manual')),
  start_at INTEGER NOT NULL,
  end_at INTEGER,
  note TEXT,
  source TEXT NOT NULL DEFAULT 'app' CHECK (source IN ('app','notification','manual','voice','import')),
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  deleted_at INTEGER,
  CHECK (end_at IS NULL OR end_at > start_at)
);
CREATE INDEX idx_time_entries_start ON time_entries(start_at);
CREATE INDEX idx_time_entries_task ON time_entries(task_id);
-- Enforce one globally open entry in SQLite.
CREATE UNIQUE INDEX idx_one_open_time_entry ON time_entries((1)) WHERE end_at IS NULL AND deleted_at IS NULL;

CREATE TABLE reminders (
  id TEXT PRIMARY KEY,
  task_id TEXT NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
  scheduled_at INTEGER NOT NULL,
  timezone_name TEXT NOT NULL,
  notification_id INTEGER NOT NULL UNIQUE,
  status TEXT NOT NULL DEFAULT 'scheduled' CHECK (status IN ('scheduled','fired','snoozed','completed','dismissed','cancelled')),
  snoozed_from_id TEXT REFERENCES reminders(id) ON DELETE SET NULL,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);
CREATE INDEX idx_reminders_scheduled ON reminders(status, scheduled_at);

CREATE TABLE daily_notes (
  id TEXT PRIMARY KEY,
  local_date TEXT NOT NULL UNIQUE,
  note TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);

CREATE TABLE generated_summaries (
  id TEXT PRIMARY KEY,
  range_start INTEGER NOT NULL,
  range_end INTEGER NOT NULL,
  summary_type TEXT NOT NULL CHECK (summary_type IN ('local','ai')),
  content TEXT NOT NULL,
  provider TEXT,
  model TEXT,
  input_hash TEXT,
  created_at INTEGER NOT NULL
);
CREATE INDEX idx_summaries_range ON generated_summaries(range_start, range_end);

CREATE TABLE app_settings (
  key TEXT PRIMARY KEY,
  value_json TEXT NOT NULL,
  updated_at INTEGER NOT NULL
);

CREATE TABLE schema_migrations (
  version INTEGER PRIMARY KEY,
  applied_at INTEGER NOT NULL,
  description TEXT NOT NULL
);
