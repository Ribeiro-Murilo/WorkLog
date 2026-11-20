import type { DatabaseSync } from "node:sqlite";
import { runInTransaction } from "../data/database";
import {
  SHORTCUT_ACTIONS,
  type AppSettings,
  type Comment,
  type Invoice,
  type InvoiceLineItem,
  type Project,
  type ReportColumn,
  type ReportPreset,
  type Session,
  type SessionWorkPeriod,
  type ShortcutAction,
  type ShortcutBinding
} from "../../src/shared/types";
import type { CommentRepository } from "./commentRepository";
import type { InvoiceRepository } from "./invoiceRepository";
import type { ProjectRepository } from "./projectRepository";
import type { ReportPresetRepository } from "./reportPresetRepository";
import type { SessionRepository } from "./sessionRepository";
import type { SettingsRepository } from "./settingsRepository";
import { DEFAULT_WINDOWS_SHORTCUTS, type ShortcutRepository } from "./shortcutRepository";

/** Apple Reference Date: 2001-01-01T00:00:00Z em segundos Unix. */
const APPLE_REFERENCE_OFFSET_SECONDS = 978307200;

export function isoToAppleSeconds(iso: string): number {
  const ms = Date.parse(iso);
  if (!Number.isFinite(ms)) return 0;
  return ms / 1000 - APPLE_REFERENCE_OFFSET_SECONDS;
}

export function appleSecondsToIso(value: unknown, fallbackIso?: string): string {
  if (typeof value === "number" && Number.isFinite(value)) {
    return new Date((value + APPLE_REFERENCE_OFFSET_SECONDS) * 1000).toISOString();
  }
  if (typeof value === "string") {
    const parsed = Date.parse(value);
    if (Number.isFinite(parsed)) return new Date(parsed).toISOString();
  }
  return fallbackIso ?? new Date().toISOString();
}

// Mapeamento bidirecional Carbon HIToolbox <-> Electron Accelerator para portabilidade macOS <-> Windows
const CARBON_TO_KEY: Record<number, string> = {
  0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
  11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T",
  18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9", 26: "7",
  27: "-", 28: "8", 29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P",
  37: "L", 38: "J", 40: "K", 41: ";", 45: "N", 46: "M", 49: "Space"
};
const KEY_TO_CARBON: Record<string, number> = Object.fromEntries(
  Object.entries(CARBON_TO_KEY).map(([code, key]) => [key.toUpperCase(), Number(code)])
);

const CARBON_CMD = 256;
const CARBON_SHIFT = 512;
const CARBON_OPTION = 2048;
const CARBON_CTRL = 4096;

export function acceleratorToCarbon(accelerator: string): { keyCode: number; modifiers: number } {
  const parts = accelerator.split("+").map((p) => p.trim());
  let modifiers = 0;
  let keyCode = 1; // fallback 'S'
  for (const part of parts) {
    const lower = part.toLowerCase();
    if (lower === "commandorcontrol" || lower === "ctrl" || lower === "control" || lower === "cmd") {
      modifiers |= CARBON_CMD;
    } else if (lower === "shift") {
      modifiers |= CARBON_SHIFT;
    } else if (lower === "alt" || lower === "option") {
      modifiers |= CARBON_OPTION;
    } else if (lower === "super" || lower === "meta") {
      modifiers |= CARBON_CTRL;
    } else {
      const code = KEY_TO_CARBON[part.toUpperCase()];
      if (code !== undefined) keyCode = code;
    }
  }
  return { keyCode, modifiers };
}

export function carbonToAccelerator(keyCode: number, modifiers: number, action: ShortcutAction): string {
  const key = CARBON_TO_KEY[keyCode];
  if (!key) return DEFAULT_WINDOWS_SHORTCUTS[action];
  const mods: string[] = [];
  if (modifiers & CARBON_CMD) mods.push("CommandOrControl");
  else if (modifiers & CARBON_CTRL) mods.push("Control");
  if (modifiers & CARBON_OPTION) mods.push("Alt");
  if (modifiers & CARBON_SHIFT) mods.push("Shift");
  if (mods.length === 0) mods.push("CommandOrControl", "Shift");
  return [...mods, key].join("+");
}

function encodeWorkPeriodsBase64(periods: SessionWorkPeriod[] | null): string | undefined {
  if (!periods || periods.length === 0) return undefined;
  const swiftPeriods = periods.map((p) => {
    const obj: { start: number; end?: number } = { start: isoToAppleSeconds(p.start) };
    if (p.end) obj.end = isoToAppleSeconds(p.end);
    return obj;
  });
  return Buffer.from(JSON.stringify(swiftPeriods), "utf8").toString("base64");
}

function decodeWorkPeriodsBase64(raw: unknown): SessionWorkPeriod[] | null {
  if (typeof raw !== "string" || raw.length === 0) return null;
  try {
    const json = Buffer.from(raw, "base64").toString("utf8");
    const parsed = JSON.parse(json);
    if (!Array.isArray(parsed)) return null;
    return parsed.map((item) => ({
      start: appleSecondsToIso(item.start),
      end: item.end !== undefined && item.end !== null ? appleSecondsToIso(item.end) : null
    }));
  } catch {
    return null;
  }
}

export class BackupArchiveError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "BackupArchiveError";
  }
}

export const BACKUP_ERROR_MESSAGES = {
  unsupportedVersion: "Este backup foi criado por uma versão mais recente do WorkLog.",
  invalidArchive: "O arquivo de backup contém registros inválidos ou repetidos."
} as const;

export class BackupService {
  constructor(
    private readonly db: DatabaseSync,
    private readonly projectRepository: ProjectRepository,
    private readonly sessionRepository: SessionRepository,
    private readonly commentRepository: CommentRepository,
    private readonly reportPresetRepository: ReportPresetRepository,
    private readonly invoiceRepository: InvoiceRepository,
    private readonly settingsRepository: SettingsRepository,
    private readonly shortcutRepository: ShortcutRepository
  ) {}

  exportBackupJson(now: Date = new Date()): string {
    const projects = this.projectRepository
      .fetchAll(true)
      .sort((a, b) => a.id.localeCompare(b.id))
      .map((p) => ({
        category: p.category,
        client: p.client,
        createdAt: isoToAppleSeconds(p.createdAt),
        dailyRate: p.dailyRate,
        descriptionText: p.descriptionText,
        id: p.id,
        isArchived: p.isArchived,
        isFavorite: p.isFavorite,
        name: p.name,
        status: p.status,
        tags: p.tags,
        updatedAt: isoToAppleSeconds(p.updatedAt)
      }));

    const sessions = this.sessionRepository
      .fetchAll(null)
      .sort((a, b) => a.id.localeCompare(b.id))
      .map((s) => {
        const base: Record<string, unknown> = {
          category: s.category,
          createdAt: isoToAppleSeconds(s.createdAt),
          date: isoToAppleSeconds(s.date),
          durationSeconds: s.durationSeconds,
          id: s.id,
          note: s.note,
          startTime: isoToAppleSeconds(s.startTime),
          status: s.status,
          updatedAt: isoToAppleSeconds(s.updatedAt)
        };
        if (s.projectId) base.projectId = s.projectId;
        if (s.endTime) base.endTime = isoToAppleSeconds(s.endTime);
        const wp = encodeWorkPeriodsBase64(s.workPeriods);
        if (wp) base.workPeriodsData = wp;
        return base;
      });

    const comments = this.commentRepository
      .fetchAll()
      .sort((a, b) => a.id.localeCompare(b.id))
      .map((c) => {
        const base: Record<string, unknown> = {
          author: c.author,
          createdAt: isoToAppleSeconds(c.createdAt),
          id: c.id,
          text: c.text
        };
        if (c.projectId) base.projectId = c.projectId;
        return base;
      });

    const reportPresets = this.reportPresetRepository
      .fetchAll()
      .sort((a, b) => a.id.localeCompare(b.id))
      .map((preset) => ({
        columnsRaw: preset.columns,
        createdAt: isoToAppleSeconds(preset.createdAt),
        groupingRaw: preset.grouping,
        id: preset.id,
        name: preset.name,
        updatedAt: isoToAppleSeconds(preset.updatedAt)
      }));

    const invoices = this.invoiceRepository
      .fetchAll()
      .sort((a, b) => a.id.localeCompare(b.id))
      .map((inv) => ({
        client: inv.client,
        createdAt: isoToAppleSeconds(inv.createdAt),
        id: inv.id,
        issueDate: isoToAppleSeconds(inv.issueDate),
        lineItems: inv.lineItems.map((li) => ({
          date: isoToAppleSeconds(li.date),
          durationSeconds: li.durationSeconds,
          projectName: li.projectName,
          value: li.value
        })),
        notes: inv.notes,
        number: inv.number,
        periodEnd: isoToAppleSeconds(inv.periodEnd),
        periodStart: isoToAppleSeconds(inv.periodStart),
        status: inv.status,
        totalValue: inv.totalValue,
        updatedAt: isoToAppleSeconds(inv.updatedAt)
      }));

    const settings = this.settingsRepository
      .fetchAll()
      .sort((a, b) => a.id.localeCompare(b.id))
      .map((st) => {
        const base: Record<string, unknown> = {
          createdAt: isoToAppleSeconds(st.createdAt),
          displayMode: st.displayMode,
          id: st.id,
          idleTimeoutMinutes: st.idleTimeoutMinutes,
          includeLogoInPDF: st.includeLogoInPDF,
          invoiceIssuerDetails: st.invoiceIssuerDetails,
          invoiceIssuerName: st.invoiceIssuerName,
          lastInvoiceNumber: st.lastInvoiceNumber,
          launchAtLogin: st.launchAtLogin,
          showSeconds: st.showSeconds,
          theme: st.theme,
          timeFormat: st.timeFormat,
          updatedAt: isoToAppleSeconds(st.updatedAt)
        };
        if (st.lastBackupDate) base.lastBackupDate = isoToAppleSeconds(st.lastBackupDate);
        return base;
      });

    const shortcuts = this.shortcutRepository
      .fetchAll()
      .sort((a, b) => a.action.localeCompare(b.action))
      .map((sb) => {
        const carbon = acceleratorToCarbon(sb.accelerator);
        return {
          actionRawValue: sb.action,
          isEnabled: sb.isEnabled,
          keyCode: carbon.keyCode,
          modifiers: carbon.modifiers,
          updatedAt: isoToAppleSeconds(sb.updatedAt),
          windowsAccelerator: sb.accelerator
        };
      });

    const archive = {
      comments,
      exportedAt: isoToAppleSeconds(now.toISOString()),
      formatVersion: 2,
      invoices,
      projects,
      reportPresets,
      sessions,
      settings,
      shortcuts
    };

    this.settingsRepository.save({ lastBackupDate: now.toISOString() });
    return JSON.stringify(archive, null, 2);
  }

  importBackupJson(rawJson: string): void {
    let parsed: Record<string, unknown>;
    try {
      const obj = JSON.parse(rawJson);
      if (!obj || typeof obj !== "object" || Array.isArray(obj)) {
        throw new BackupArchiveError(BACKUP_ERROR_MESSAGES.invalidArchive);
      }
      parsed = obj as Record<string, unknown>;
    } catch (error) {
      if (error instanceof BackupArchiveError) throw error;
      throw new BackupArchiveError(BACKUP_ERROR_MESSAGES.invalidArchive);
    }

    if ("formatVersion" in parsed && parsed.formatVersion !== undefined) {
      if (parsed.formatVersion !== 2) {
        throw new BackupArchiveError(BACKUP_ERROR_MESSAGES.unsupportedVersion);
      }
    } else {
      // Suporte ao formato legado v1 (datas ISO8601, apenas projects e sessions)
      if (
        typeof parsed.exportedAt !== "string" ||
        !Array.isArray(parsed.projects) ||
        !Array.isArray(parsed.sessions)
      ) {
        throw new BackupArchiveError(BACKUP_ERROR_MESSAGES.invalidArchive);
      }
      const fallback = parsed.exportedAt;
      parsed = {
        formatVersion: 2,
        exportedAt: fallback,
        projects: parsed.projects.map((p: Record<string, unknown>) => ({
          ...p,
          createdAt: p.createdAt ?? fallback,
          updatedAt: p.updatedAt ?? fallback
        })),
        sessions: parsed.sessions.map((s: Record<string, unknown>) => ({
          ...s,
          createdAt: s.createdAt ?? fallback,
          updatedAt: s.updatedAt ?? fallback
        })),
        comments: [],
        reportPresets: [],
        invoices: [],
        settings: [],
        shortcuts: []
      };
    }

    const projectsRaw = Array.isArray(parsed.projects) ? parsed.projects : null;
    const sessionsRaw = Array.isArray(parsed.sessions) ? parsed.sessions : null;
    const commentsRaw = Array.isArray(parsed.comments) ? parsed.comments : null;
    const presetsRaw = Array.isArray(parsed.reportPresets) ? parsed.reportPresets : null;
    const invoicesRaw = Array.isArray(parsed.invoices) ? parsed.invoices : null;
    const settingsRaw = Array.isArray(parsed.settings) ? parsed.settings : null;
    const shortcutsRaw = Array.isArray(parsed.shortcuts) ? parsed.shortcuts : null;

    if (
      !projectsRaw ||
      !sessionsRaw ||
      !commentsRaw ||
      !presetsRaw ||
      !invoicesRaw ||
      !settingsRaw ||
      !shortcutsRaw
    ) {
      throw new BackupArchiveError(BACKUP_ERROR_MESSAGES.invalidArchive);
    }

    const projects = projectsRaw.map(parseProjectPayload);
    const sessions = sessionsRaw.map(parseSessionPayload);
    const comments = commentsRaw.map(parseCommentPayload);
    const presets = presetsRaw.map(parsePresetPayload);
    const invoices = invoicesRaw.map(parseInvoicePayload);
    const settingsList = settingsRaw.map(parseSettingsPayload);
    const shortcuts = shortcutsRaw.map(parseShortcutPayload);

    assertUniqueIds(projects.map((p) => p.id));
    assertUniqueIds(sessions.map((s) => s.id));
    assertUniqueIds(comments.map((c) => c.id));
    assertUniqueIds(presets.map((p) => p.id));
    assertUniqueIds(invoices.map((i) => i.id));
    assertUniqueIds(settingsList.map((s) => s.id));
    assertUniqueIds(shortcuts.map((s) => s.action));

    const projectIds = new Set(projects.map((p) => p.id));

    runInTransaction(this.db, () => {
      const previousMaxInvoice = this.settingsRepository
        .fetchAll()
        .reduce((max, s) => Math.max(max, s.lastInvoiceNumber), 0);

      // Substituição integral limpa (espelha stage do Swift)
      this.commentRepository.deleteAll();
      this.sessionRepository.deleteAll();
      this.projectRepository.deleteAll();
      this.reportPresetRepository.deleteAll();
      this.invoiceRepository.deleteAll();

      for (const project of projects) {
        this.projectRepository.upsertRaw(project);
      }
      for (const session of sessions) {
        this.sessionRepository.upsertRaw({
          ...session,
          projectId: session.projectId && projectIds.has(session.projectId) ? session.projectId : null
        });
      }
      for (const comment of comments) {
        this.commentRepository.upsertRaw({
          ...comment,
          projectId: comment.projectId && projectIds.has(comment.projectId) ? comment.projectId : null
        });
      }
      for (const preset of presets) {
        this.reportPresetRepository.upsertRaw(preset);
      }
      for (const invoice of invoices) {
        this.invoiceRepository.upsertRaw(invoice);
      }
      if (settingsList.length > 0) {
        const restoredIds = new Set(settingsList.map((s) => s.id));
        this.settingsRepository.deleteAllExcept(restoredIds);
        for (const item of settingsList) {
          this.settingsRepository.upsertRaw(item);
        }
      }
      for (const sb of shortcuts) {
        this.shortcutRepository.upsert(sb.action, sb.accelerator, sb.isEnabled, sb.updatedAt);
      }

      const archiveMaxInvoice = settingsList.reduce(
        (max, s) => Math.max(max, s.lastInvoiceNumber),
        0
      );
      this.settingsRepository.raiseInvoiceCounter(Math.max(previousMaxInvoice, archiveMaxInvoice));
    });
  }
}

function assertUniqueIds(ids: string[]): void {
  if (new Set(ids).size !== ids.length) {
    throw new BackupArchiveError(BACKUP_ERROR_MESSAGES.invalidArchive);
  }
}

function asObject(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new BackupArchiveError(BACKUP_ERROR_MESSAGES.invalidArchive);
  }
  return value as Record<string, unknown>;
}

function requireString(obj: Record<string, unknown>, key: string): string {
  const val = obj[key];
  if (typeof val !== "string" || val.length === 0) {
    throw new BackupArchiveError(BACKUP_ERROR_MESSAGES.invalidArchive);
  }
  return val;
}

function parseProjectPayload(raw: unknown): Project {
  const o = asObject(raw);
  return {
    id: requireString(o, "id"),
    name: typeof o.name === "string" ? o.name : "",
    client: typeof o.client === "string" ? o.client : "",
    dailyRate: Number(o.dailyRate) || 0,
    category: o.category === "personal" ? "personal" : "work",
    tags: Array.isArray(o.tags) ? o.tags.map(String) : [],
    descriptionText: typeof o.descriptionText === "string" ? o.descriptionText : "",
    status: (["active", "inProgress", "blocked", "ready"].includes(String(o.status))
      ? String(o.status)
      : "active") as Project["status"],
    isArchived: Boolean(o.isArchived),
    isFavorite: Boolean(o.isFavorite),
    createdAt: appleSecondsToIso(o.createdAt),
    updatedAt: appleSecondsToIso(o.updatedAt)
  };
}

function parseSessionPayload(raw: unknown): Session {
  const o = asObject(raw);
  return {
    id: requireString(o, "id"),
    projectId: typeof o.projectId === "string" ? o.projectId : null,
    date: appleSecondsToIso(o.date),
    startTime: appleSecondsToIso(o.startTime),
    endTime: o.endTime !== undefined && o.endTime !== null ? appleSecondsToIso(o.endTime) : null,
    durationSeconds: Number(o.durationSeconds) || 0,
    workPeriods: decodeWorkPeriodsBase64(o.workPeriodsData),
    note: typeof o.note === "string" ? o.note : "",
    category: o.category === "personal" ? "personal" : "work",
    status: (["running", "paused", "completed"].includes(String(o.status))
      ? String(o.status)
      : "completed") as Session["status"],
    createdAt: appleSecondsToIso(o.createdAt),
    updatedAt: appleSecondsToIso(o.updatedAt)
  };
}

function parseCommentPayload(raw: unknown): Comment {
  const o = asObject(raw);
  return {
    id: requireString(o, "id"),
    projectId: typeof o.projectId === "string" ? o.projectId : null,
    text: typeof o.text === "string" ? o.text : "",
    author: typeof o.author === "string" ? o.author : "",
    createdAt: appleSecondsToIso(o.createdAt)
  };
}

function parsePresetPayload(raw: unknown): ReportPreset {
  const o = asObject(raw);
  return {
    id: requireString(o, "id"),
    name: typeof o.name === "string" ? o.name : "",
    columns: Array.isArray(o.columnsRaw) ? (o.columnsRaw as ReportColumn[]) : [],
    grouping: o.groupingRaw === "byProjectAndDay" ? "byProjectAndDay" : "detailed",
    createdAt: appleSecondsToIso(o.createdAt),
    updatedAt: appleSecondsToIso(o.updatedAt)
  };
}

function parseInvoicePayload(raw: unknown): Invoice {
  const o = asObject(raw);
  const num = Number(o.number) || 0;
  const lineItems: InvoiceLineItem[] = Array.isArray(o.lineItems)
    ? o.lineItems.map((item) => {
        const li = asObject(item);
        return {
          date: appleSecondsToIso(li.date),
          projectName: typeof li.projectName === "string" ? li.projectName : "",
          durationSeconds: Number(li.durationSeconds) || 0,
          value: Number(li.value) || 0
        };
      })
    : [];
  return {
    id: requireString(o, "id"),
    number: num,
    formattedNumber: `FAT-${String(num).padStart(4, "0")}`,
    client: typeof o.client === "string" ? o.client : "",
    issueDate: appleSecondsToIso(o.issueDate),
    periodStart: appleSecondsToIso(o.periodStart),
    periodEnd: appleSecondsToIso(o.periodEnd),
    lineItems,
    totalDurationSeconds: lineItems.reduce((acc, i) => acc + i.durationSeconds, 0),
    totalValue: Number(o.totalValue) || 0,
    status: o.status === "paid" ? "paid" : "pending",
    notes: typeof o.notes === "string" ? o.notes : "",
    createdAt: appleSecondsToIso(o.createdAt),
    updatedAt: appleSecondsToIso(o.updatedAt)
  };
}

function parseSettingsPayload(raw: unknown): AppSettings {
  const o = asObject(raw);
  return {
    id: requireString(o, "id"),
    launchAtLogin: Boolean(o.launchAtLogin ?? true),
    idleTimeoutMinutes: Number(o.idleTimeoutMinutes) || 10,
    showSeconds: Boolean(o.showSeconds ?? true),
    theme: (["system", "light", "dark"].includes(String(o.theme))
      ? String(o.theme)
      : "system") as AppSettings["theme"],
    timeFormat: o.timeFormat === "twelveHour" ? "twelveHour" : "twentyFourHour",
    displayMode: o.displayMode === "menuBar" ? "menuBar" : "notch",
    notchDisplayId: typeof o.notchDisplayId === "string" ? o.notchDisplayId : null,
    lastBackupDate:
      o.lastBackupDate !== undefined && o.lastBackupDate !== null
        ? appleSecondsToIso(o.lastBackupDate)
        : null,
    invoiceIssuerName: typeof o.invoiceIssuerName === "string" ? o.invoiceIssuerName : "",
    invoiceIssuerDetails: typeof o.invoiceIssuerDetails === "string" ? o.invoiceIssuerDetails : "",
    lastInvoiceNumber: Number(o.lastInvoiceNumber) || 0,
    includeLogoInPDF: Boolean(o.includeLogoInPDF ?? false),
    createdAt: appleSecondsToIso(o.createdAt),
    updatedAt: appleSecondsToIso(o.updatedAt)
  };
}

function parseShortcutPayload(raw: unknown): ShortcutBinding {
  const o = asObject(raw);
  const action = requireString(o, "actionRawValue") as ShortcutAction;
  if (!SHORTCUT_ACTIONS.includes(action)) {
    throw new BackupArchiveError(BACKUP_ERROR_MESSAGES.invalidArchive);
  }
  const accelerator =
    typeof o.windowsAccelerator === "string" && o.windowsAccelerator.length > 0
      ? o.windowsAccelerator
      : carbonToAccelerator(Number(o.keyCode) || 0, Number(o.modifiers) || 0, action);
  return {
    action,
    accelerator,
    isEnabled: Boolean(o.isEnabled ?? true),
    updatedAt: appleSecondsToIso(o.updatedAt)
  };
}
