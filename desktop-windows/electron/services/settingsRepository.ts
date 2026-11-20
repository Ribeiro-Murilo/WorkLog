import crypto from "node:crypto";
import type { DatabaseSync } from "node:sqlite";
import type {
  AppDisplayMode,
  AppSettings,
  AppTheme,
  TimeFormatPreference
} from "../../src/shared/types";

interface SettingsRow {
  id: string;
  launch_at_login: number;
  idle_timeout_minutes: number;
  show_seconds: number;
  theme: string;
  time_format: string;
  display_mode: string;
  notch_display_id: string | null;
  last_backup_date: string | null;
  invoice_issuer_name: string;
  invoice_issuer_details: string;
  last_invoice_number: number;
  include_logo_in_pdf: number;
  created_at: string;
  updated_at: string;
}

function mapSettings(row: SettingsRow): AppSettings {
  return {
    id: row.id,
    launchAtLogin: row.launch_at_login === 1,
    idleTimeoutMinutes: Number(row.idle_timeout_minutes) || 10,
    showSeconds: row.show_seconds === 1,
    theme: (["system", "light", "dark"].includes(row.theme) ? row.theme : "system") as AppTheme,
    timeFormat: (row.time_format === "twelveHour" ? "twelveHour" : "twentyFourHour") as TimeFormatPreference,
    displayMode: (row.display_mode === "menuBar" ? "menuBar" : "notch") as AppDisplayMode,
    notchDisplayId: row.notch_display_id ?? null,
    lastBackupDate: row.last_backup_date ?? null,
    invoiceIssuerName: row.invoice_issuer_name ?? "",
    invoiceIssuerDetails: row.invoice_issuer_details ?? "",
    lastInvoiceNumber: Number(row.last_invoice_number) || 0,
    includeLogoInPDF: row.include_logo_in_pdf === 1,
    createdAt: row.created_at,
    updatedAt: row.updated_at
  };
}

export class SettingsRepository {
  constructor(private readonly db: DatabaseSync) {}

  fetchAll(): AppSettings[] {
    const rows = this.db.prepare("SELECT * FROM app_settings").all() as unknown as SettingsRow[];
    return rows.map(mapSettings);
  }

  current(): AppSettings {
    const row = this.db.prepare("SELECT * FROM app_settings LIMIT 1").get() as
      | SettingsRow
      | undefined;
    if (row) return mapSettings(row);

    const now = new Date().toISOString();
    const defaults: AppSettings = {
      id: crypto.randomUUID().toUpperCase(),
      launchAtLogin: true,
      idleTimeoutMinutes: 10,
      showSeconds: true,
      theme: "system",
      timeFormat: "twentyFourHour",
      displayMode: "notch",
      notchDisplayId: null,
      lastBackupDate: null,
      invoiceIssuerName: "",
      invoiceIssuerDetails: "",
      lastInvoiceNumber: 0,
      includeLogoInPDF: false,
      createdAt: now,
      updatedAt: now
    };
    this.upsertRaw(defaults);
    return defaults;
  }

  save(patch: Partial<AppSettings>): AppSettings {
    const curr = this.current();
    const updated: AppSettings = {
      ...curr,
      ...patch,
      lastInvoiceNumber: Math.max(curr.lastInvoiceNumber, patch.lastInvoiceNumber ?? curr.lastInvoiceNumber),
      updatedAt: new Date().toISOString()
    };
    this.upsertRaw(updated);
    return updated;
  }

  raiseInvoiceCounter(minValue: number): void {
    const curr = this.current();
    if (minValue > curr.lastInvoiceNumber) {
      this.save({ lastInvoiceNumber: minValue });
    }
  }

  upsertRaw(settings: AppSettings): void {
    this.db
      .prepare(
        `INSERT INTO app_settings (
          id, launch_at_login, idle_timeout_minutes, show_seconds, theme,
          time_format, display_mode, notch_display_id, last_backup_date,
          invoice_issuer_name, invoice_issuer_details, last_invoice_number,
          include_logo_in_pdf, created_at, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
          launch_at_login = excluded.launch_at_login,
          idle_timeout_minutes = excluded.idle_timeout_minutes,
          show_seconds = excluded.show_seconds,
          theme = excluded.theme,
          time_format = excluded.time_format,
          display_mode = excluded.display_mode,
          notch_display_id = COALESCE(excluded.notch_display_id, app_settings.notch_display_id),
          last_backup_date = excluded.last_backup_date,
          invoice_issuer_name = excluded.invoice_issuer_name,
          invoice_issuer_details = excluded.invoice_issuer_details,
          last_invoice_number = MAX(app_settings.last_invoice_number, excluded.last_invoice_number),
          include_logo_in_pdf = excluded.include_logo_in_pdf,
          created_at = excluded.created_at,
          updated_at = excluded.updated_at`
      )
      .run(
        settings.id,
        settings.launchAtLogin ? 1 : 0,
        settings.idleTimeoutMinutes,
        settings.showSeconds ? 1 : 0,
        settings.theme,
        settings.timeFormat,
        settings.displayMode,
        settings.notchDisplayId,
        settings.lastBackupDate,
        settings.invoiceIssuerName,
        settings.invoiceIssuerDetails,
        settings.lastInvoiceNumber,
        settings.includeLogoInPDF ? 1 : 0,
        settings.createdAt,
        settings.updatedAt
      );
  }

  deleteAllExcept(keepIds: Set<string>): void {
    const existing = this.fetchAll();
    const stmt = this.db.prepare("DELETE FROM app_settings WHERE id = ?");
    for (const item of existing) {
      if (!keepIds.has(item.id)) stmt.run(item.id);
    }
  }
}
