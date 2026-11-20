import { DatabaseSync } from "node:sqlite";

export function openDatabase(dbPath: string): DatabaseSync {
  const db = new DatabaseSync(dbPath);
  db.exec("PRAGMA foreign_keys = ON;");
  if (dbPath !== ":memory:") {
    db.exec("PRAGMA journal_mode = WAL;");
  }

  db.exec(`
    CREATE TABLE IF NOT EXISTS projects (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      client TEXT NOT NULL,
      daily_rate REAL NOT NULL DEFAULT 0,
      category TEXT NOT NULL DEFAULT 'work',
      tags_json TEXT NOT NULL DEFAULT '[]',
      description_text TEXT NOT NULL DEFAULT '',
      status TEXT NOT NULL DEFAULT 'active',
      is_archived INTEGER NOT NULL DEFAULT 0,
      is_favorite INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    );

    CREATE TABLE IF NOT EXISTS sessions (
      id TEXT PRIMARY KEY,
      project_id TEXT REFERENCES projects(id) ON DELETE CASCADE,
      date TEXT NOT NULL,
      start_time TEXT NOT NULL,
      end_time TEXT,
      duration_seconds REAL NOT NULL DEFAULT 0,
      work_periods_json TEXT,
      note TEXT NOT NULL DEFAULT '',
      category TEXT NOT NULL DEFAULT 'work',
      status TEXT NOT NULL DEFAULT 'running',
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    );

    CREATE TABLE IF NOT EXISTS comments (
      id TEXT PRIMARY KEY,
      project_id TEXT REFERENCES projects(id) ON DELETE CASCADE,
      text TEXT NOT NULL,
      author TEXT NOT NULL,
      created_at TEXT NOT NULL
    );

    CREATE TABLE IF NOT EXISTS report_presets (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      columns_json TEXT NOT NULL DEFAULT '[]',
      grouping TEXT NOT NULL DEFAULT 'detailed',
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    );

    CREATE TABLE IF NOT EXISTS invoices (
      id TEXT PRIMARY KEY,
      number INTEGER NOT NULL,
      client TEXT NOT NULL,
      issue_date TEXT NOT NULL,
      period_start TEXT NOT NULL,
      period_end TEXT NOT NULL,
      line_items_json TEXT NOT NULL DEFAULT '[]',
      total_value REAL NOT NULL DEFAULT 0,
      status TEXT NOT NULL DEFAULT 'pending',
      notes TEXT NOT NULL DEFAULT '',
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    );

    CREATE TABLE IF NOT EXISTS app_settings (
      id TEXT PRIMARY KEY,
      launch_at_login INTEGER NOT NULL DEFAULT 1,
      idle_timeout_minutes INTEGER NOT NULL DEFAULT 10,
      show_seconds INTEGER NOT NULL DEFAULT 1,
      theme TEXT NOT NULL DEFAULT 'system',
      time_format TEXT NOT NULL DEFAULT 'twentyFourHour',
      display_mode TEXT NOT NULL DEFAULT 'notch',
      notch_display_id TEXT,
      last_backup_date TEXT,
      invoice_issuer_name TEXT NOT NULL DEFAULT '',
      invoice_issuer_details TEXT NOT NULL DEFAULT '',
      last_invoice_number INTEGER NOT NULL DEFAULT 0,
      include_logo_in_pdf INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    );

    CREATE TABLE IF NOT EXISTS shortcut_bindings (
      action TEXT PRIMARY KEY,
      accelerator TEXT NOT NULL,
      is_enabled INTEGER NOT NULL DEFAULT 1,
      updated_at TEXT NOT NULL
    );

    CREATE INDEX IF NOT EXISTS idx_sessions_project ON sessions(project_id);
    CREATE INDEX IF NOT EXISTS idx_sessions_status ON sessions(status);
    CREATE INDEX IF NOT EXISTS idx_comments_project ON comments(project_id);
    CREATE INDEX IF NOT EXISTS idx_invoices_client ON invoices(client);
  `);

  return db;
}

export function runInTransaction<T>(db: DatabaseSync, fn: () => T): T {
  db.exec("BEGIN");
  try {
    const result = fn();
    db.exec("COMMIT");
    return result;
  } catch (error) {
    try {
      db.exec("ROLLBACK");
    } catch {
      // ignora se a transação já foi fechada
    }
    throw error;
  }
}
