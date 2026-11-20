import crypto from "node:crypto";
import type { DatabaseSync } from "node:sqlite";
import type { ReportColumn, ReportGrouping, ReportPreset } from "../../src/shared/types";

interface PresetRow {
  id: string;
  name: string;
  columns_json: string;
  grouping: string;
  created_at: string;
  updated_at: string;
}

function mapPreset(row: PresetRow): ReportPreset {
  let columns: ReportColumn[] = [];
  try {
    const parsed = JSON.parse(row.columns_json);
    if (Array.isArray(parsed)) columns = parsed as ReportColumn[];
  } catch {
    columns = [];
  }
  return {
    id: row.id,
    name: row.name,
    columns,
    grouping: (row.grouping === "byProjectAndDay" ? "byProjectAndDay" : "detailed") as ReportGrouping,
    createdAt: row.created_at,
    updatedAt: row.updated_at
  };
}

export class ReportPresetRepository {
  constructor(private readonly db: DatabaseSync) {}

  fetchAll(): ReportPreset[] {
    const rows = this.db
      .prepare("SELECT * FROM report_presets ORDER BY name COLLATE NOCASE ASC")
      .all() as unknown as PresetRow[];
    return rows.map(mapPreset);
  }

  upsertByName(name: string, columns: ReportColumn[], grouping: ReportGrouping): ReportPreset {
    const trimmed = name.trim();
    if (!trimmed) throw new Error("Informe um nome para o tipo de relatório.");

    const existing = this.fetchAll().find(
      (item) => item.name.toLocaleLowerCase("pt-BR") === trimmed.toLocaleLowerCase("pt-BR")
    );
    const now = new Date().toISOString();

    if (existing) {
      this.db
        .prepare(
          "UPDATE report_presets SET name = ?, columns_json = ?, grouping = ?, updated_at = ? WHERE id = ?"
        )
        .run(trimmed, JSON.stringify(columns), grouping, now, existing.id);
      return {
        ...existing,
        name: trimmed,
        columns,
        grouping,
        updatedAt: now
      };
    }

    const preset: ReportPreset = {
      id: crypto.randomUUID().toUpperCase(),
      name: trimmed,
      columns,
      grouping,
      createdAt: now,
      updatedAt: now
    };
    this.db
      .prepare(
        "INSERT INTO report_presets (id, name, columns_json, grouping, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)"
      )
      .run(preset.id, preset.name, JSON.stringify(preset.columns), preset.grouping, preset.createdAt, preset.updatedAt);

    return preset;
  }

  upsertRaw(preset: ReportPreset): void {
    this.db
      .prepare(
        `INSERT INTO report_presets (id, name, columns_json, grouping, created_at, updated_at)
         VALUES (?, ?, ?, ?, ?, ?)
         ON CONFLICT(id) DO UPDATE SET
           name = excluded.name,
           columns_json = excluded.columns_json,
           grouping = excluded.grouping,
           created_at = excluded.created_at,
           updated_at = excluded.updated_at`
      )
      .run(
        preset.id,
        preset.name,
        JSON.stringify(preset.columns),
        preset.grouping,
        preset.createdAt,
        preset.updatedAt
      );
  }

  delete(id: string): void {
    this.db.prepare("DELETE FROM report_presets WHERE id = ?").run(id);
  }

  deleteAll(): void {
    this.db.prepare("DELETE FROM report_presets").run();
  }
}
