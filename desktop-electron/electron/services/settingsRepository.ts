import type { SqlDatabase } from "../data/database";
import type { AppSettings } from "../../src/shared/types";
import { mapSettings } from "../data/mappers";

const SETTINGS_ID = "default";

export class SettingsRepository {
  constructor(private readonly db: SqlDatabase) {}

  get(): AppSettings {
    const row = this.db.prepare("SELECT * FROM settings WHERE id = ?").get(SETTINGS_ID);
    if (row) return mapSettings(row as never);
    const now = new Date().toISOString();
    this.db
      .prepare(
        `INSERT INTO settings (
          id, launch_at_login, idle_timeout_minutes, show_seconds, theme,
          time_format, last_backup_date, created_at, updated_at
        ) VALUES (?, 1, 10, 1, 'system', 'twentyFourHour', NULL, ?, ?)`
      )
      .run(SETTINGS_ID, now, now);
    return this.get();
  }

  update(input: Partial<AppSettings>): AppSettings {
    const current = this.get();
    const next: AppSettings = { ...current, ...input, updatedAt: new Date().toISOString() };
    this.db
      .prepare(
        `UPDATE settings SET
          launch_at_login = ?, idle_timeout_minutes = ?, show_seconds = ?,
          theme = ?, time_format = ?, last_backup_date = ?, updated_at = ?
         WHERE id = ?`
      )
      .run(
        next.launchAtLogin ? 1 : 0,
        next.idleTimeoutMinutes,
        next.showSeconds ? 1 : 0,
        next.theme,
        next.timeFormat,
        next.lastBackupDate,
        next.updatedAt,
        SETTINGS_ID
      );
    return this.get();
  }
}
