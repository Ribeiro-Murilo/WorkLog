import type { DatabaseSync } from "node:sqlite";
import { SHORTCUT_ACTIONS, type ShortcutAction, type ShortcutBinding } from "../../src/shared/types";

export const DEFAULT_WINDOWS_SHORTCUTS: Record<ShortcutAction, string> = {
  startTimer: "CommandOrControl+Shift+S",
  pauseTimer: "CommandOrControl+Shift+P",
  openDashboard: "CommandOrControl+Shift+D",
  openPopover: "CommandOrControl+Shift+W",
  searchProject: "CommandOrControl+Shift+F",
  newProject: "CommandOrControl+Shift+N"
};

interface ShortcutRow {
  action: string;
  accelerator: string;
  is_enabled: number;
  updated_at: string;
}

function mapShortcut(row: ShortcutRow): ShortcutBinding {
  return {
    action: row.action as ShortcutAction,
    accelerator: row.accelerator,
    isEnabled: row.is_enabled === 1,
    updatedAt: row.updated_at
  };
}

export class ShortcutRepository {
  constructor(private readonly db: DatabaseSync) {}

  ensureDefaults(): ShortcutBinding[] {
    const now = new Date().toISOString();
    for (const action of SHORTCUT_ACTIONS) {
      if (!this.fetchByAction(action)) {
        this.upsert(action, DEFAULT_WINDOWS_SHORTCUTS[action], true, now);
      }
    }
    return this.fetchAll();
  }

  fetchAll(): ShortcutBinding[] {
    const rows = this.db.prepare("SELECT * FROM shortcut_bindings").all() as unknown as ShortcutRow[];
    return rows.map(mapShortcut);
  }

  fetchByAction(action: ShortcutAction): ShortcutBinding | null {
    const row = this.db
      .prepare("SELECT * FROM shortcut_bindings WHERE action = ?")
      .get(action) as ShortcutRow | undefined;
    return row ? mapShortcut(row) : null;
  }

  upsert(action: ShortcutAction, accelerator: string, isEnabled: boolean, updatedAt?: string): ShortcutBinding {
    const ts = updatedAt ?? new Date().toISOString();
    this.db
      .prepare(
        `INSERT INTO shortcut_bindings (action, accelerator, is_enabled, updated_at)
         VALUES (?, ?, ?, ?)
         ON CONFLICT(action) DO UPDATE SET
           accelerator = excluded.accelerator,
           is_enabled = excluded.is_enabled,
           updated_at = excluded.updated_at`
      )
      .run(action, accelerator, isEnabled ? 1 : 0, ts);
    return this.fetchByAction(action)!;
  }
}
