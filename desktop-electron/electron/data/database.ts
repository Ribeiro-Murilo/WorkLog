import { app } from "electron";
import fs from "node:fs";
import path from "node:path";
import initSqlJs, { type Database as SqlJsDatabase, type SqlJsStatic } from "sql.js";

type SqlValue = string | number | null;

export class SqlDatabase {
  constructor(
    private readonly db: SqlJsDatabase,
    private readonly dbPath: string
  ) {}

  exec(sql: string): void {
    this.db.run(sql);
    this.persist();
  }

  prepare(sql: string): SqlStatement {
    return new SqlStatement(this.db, sql, () => this.persist());
  }

  close(): void {
    this.persist();
    this.db.close();
  }

  private persist(): void {
    fs.writeFileSync(this.dbPath, Buffer.from(this.db.export()));
  }
}

class SqlStatement {
  constructor(
    private readonly db: SqlJsDatabase,
    private readonly sql: string,
    private readonly persist: () => void
  ) {}

  all(...params: SqlValue[]): Record<string, unknown>[] {
    const stmt = this.db.prepare(this.sql);
    try {
      stmt.bind(params);
      const rows: Record<string, unknown>[] = [];
      while (stmt.step()) {
        rows.push(stmt.getAsObject());
      }
      return rows;
    } finally {
      stmt.free();
    }
  }

  get(...params: SqlValue[]): Record<string, unknown> | undefined {
    return this.all(...params)[0];
  }

  run(...params: SqlValue[]): void {
    const stmt = this.db.prepare(this.sql);
    try {
      stmt.run(params);
      this.persist();
    } finally {
      stmt.free();
    }
  }
}

let connection: SqlDatabase | null = null;

export async function getDatabase(): Promise<SqlDatabase> {
  if (connection) return connection;

  const dataDir = app.getPath("userData");
  fs.mkdirSync(dataDir, { recursive: true });
  const dbPath = path.join(dataDir, "worklog.sqlite");
  const SQL = await loadSqlJs();
  const data = fs.existsSync(dbPath) ? fs.readFileSync(dbPath) : undefined;
  connection = new SqlDatabase(new SQL.Database(data), dbPath);
  migrate(connection);
  return connection;
}

async function loadSqlJs(): Promise<SqlJsStatic> {
  return initSqlJs({
    locateFile: (file) => {
      const localPath = path.join(__dirname, "../../node_modules/sql.js/dist", file);
      if (fs.existsSync(localPath)) return localPath;
      return path.join(process.resourcesPath, "node_modules/sql.js/dist", file);
    }
  });
}

function migrate(db: SqlDatabase): void {
  db.exec(`
    PRAGMA foreign_keys = ON;

    CREATE TABLE IF NOT EXISTS projects (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      client TEXT NOT NULL,
      daily_rate REAL NOT NULL DEFAULT 0,
      category TEXT NOT NULL,
      tags TEXT NOT NULL DEFAULT '[]',
      description_text TEXT NOT NULL DEFAULT '',
      status TEXT NOT NULL,
      is_archived INTEGER NOT NULL DEFAULT 0,
      is_favorite INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    );

    CREATE TABLE IF NOT EXISTS sessions (
      id TEXT PRIMARY KEY,
      project_id TEXT,
      date TEXT NOT NULL,
      start_time TEXT NOT NULL,
      end_time TEXT,
      duration_seconds REAL NOT NULL DEFAULT 0,
      note TEXT NOT NULL DEFAULT '',
      category TEXT NOT NULL,
      status TEXT NOT NULL,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      FOREIGN KEY(project_id) REFERENCES projects(id) ON DELETE CASCADE
    );

    CREATE TABLE IF NOT EXISTS settings (
      id TEXT PRIMARY KEY,
      launch_at_login INTEGER NOT NULL DEFAULT 1,
      idle_timeout_minutes INTEGER NOT NULL DEFAULT 10,
      show_seconds INTEGER NOT NULL DEFAULT 1,
      theme TEXT NOT NULL DEFAULT 'system',
      time_format TEXT NOT NULL DEFAULT 'twentyFourHour',
      last_backup_date TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    );

    CREATE INDEX IF NOT EXISTS idx_projects_name_client ON projects(name, client);
    CREATE INDEX IF NOT EXISTS idx_projects_archived ON projects(is_archived);
    CREATE INDEX IF NOT EXISTS idx_sessions_project ON sessions(project_id);
    CREATE INDEX IF NOT EXISTS idx_sessions_start_time ON sessions(start_time);
    CREATE INDEX IF NOT EXISTS idx_sessions_status ON sessions(status);
  `);
}

export function closeDatabase(): void {
  connection?.close();
  connection = null;
}
