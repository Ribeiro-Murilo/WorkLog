import { describe, expect, it } from "vitest";
import { openDatabase } from "../electron/data/database";
import { BackupService, isoToAppleSeconds } from "../electron/services/backupService";
import { CommentRepository } from "../electron/services/commentRepository";
import { InvoiceRepository } from "../electron/services/invoiceRepository";
import { ProjectRepository } from "../electron/services/projectRepository";
import { ReportPresetRepository } from "../electron/services/reportPresetRepository";
import { SessionRepository } from "../electron/services/sessionRepository";
import { SettingsRepository } from "../electron/services/settingsRepository";
import { ShortcutRepository } from "../electron/services/shortcutRepository";

function createServices() {
  const db = openDatabase(":memory:");
  const projects = new ProjectRepository(db);
  const sessions = new SessionRepository(db);
  const comments = new CommentRepository(db);
  const presets = new ReportPresetRepository(db);
  const settings = new SettingsRepository(db);
  const invoices = new InvoiceRepository(db, settings);
  const shortcuts = new ShortcutRepository(db);
  const backup = new BackupService(
    db,
    projects,
    sessions,
    comments,
    presets,
    invoices,
    settings,
    shortcuts
  );
  return { db, projects, sessions, comments, presets, settings, invoices, shortcuts, backup };
}

describe("backup", () => {
  it("exporta e importa formatVersion 2 compatível com macOS (Apple Reference Date + workPeriodsData base64)", () => {
    const src = createServices();
    src.shortcuts.ensureDefaults();
    src.settings.save({ invoiceIssuerName: "Murilo Dev", lastInvoiceNumber: 5 });
    const proj = src.projects.insert({
      name: "WorkLog",
      client: "Interno",
      dailyRate: 1000,
      category: "work",
      tags: ["swift", "win"],
      descriptionText: "Port",
      status: "inProgress"
    });
    src.comments.insert({ projectId: proj.id, text: "Nota inicial", author: "Murilo" });
    src.presets.upsertByName("Padrão", ["project", "duration"], "detailed");
    src.sessions.insert({
      projectId: proj.id,
      date: "2026-10-10T09:00:00.000Z",
      startTime: "2026-10-10T09:00:00.000Z",
      endTime: "2026-10-10T11:00:00.000Z",
      durationSeconds: 3600,
      workPeriods: [
        { start: "2026-10-10T09:00:00.000Z", end: "2026-10-10T09:30:00.000Z" },
        { start: "2026-10-10T10:30:00.000Z", end: "2026-10-10T11:00:00.000Z" }
      ],
      note: "Ciclos",
      category: "work",
      status: "completed"
    });

    const json = src.backup.exportBackupJson(new Date("2026-10-15T12:00:00.000Z"));
    const parsed = JSON.parse(json);
    expect(parsed.formatVersion).toBe(2);
    expect(typeof parsed.exportedAt).toBe("number");
    expect(parsed.exportedAt).toBeCloseTo(isoToAppleSeconds("2026-10-15T12:00:00.000Z"), 2);
    expect(typeof parsed.sessions[0].workPeriodsData).toBe("string");

    // Restaura em banco limpo com contador maior prévio (monotonicidade preservada)
    const dst = createServices();
    dst.settings.save({ lastInvoiceNumber: 9 });
    dst.backup.importBackupJson(json);

    expect(dst.projects.fetchAll(true)).toHaveLength(1);
    expect(dst.projects.fetchAll(true)[0].name).toBe("WorkLog");
    expect(dst.sessions.fetchAll(null)[0].workPeriods).toHaveLength(2);
    expect(dst.comments.fetchAll()).toHaveLength(1);
    expect(dst.presets.fetchAll()).toHaveLength(1);
    expect(dst.settings.current().lastInvoiceNumber).toBe(9);
    expect(dst.settings.current().invoiceIssuerName).toBe("Murilo Dev");

    src.db.close();
    dst.db.close();
  });

  it("aceita backup legado v1 ISO8601 e reverte transação em arquivo com IDs duplicados", () => {
    const svc = createServices();
    const existing = svc.projects.insert({
      name: "Original",
      client: "C",
      dailyRate: 100,
      category: "work",
      tags: [],
      descriptionText: "",
      status: "active"
    });

    const legacyV1 = JSON.stringify({
      exportedAt: "2026-07-01T10:00:00Z",
      projects: [
        {
          id: "11111111-1111-1111-1111-111111111111",
          name: "Legado",
          client: "Cliente V1",
          dailyRate: 500,
          category: "work",
          tags: [],
          descriptionText: "",
          status: "active",
          isArchived: false,
          isFavorite: false
        }
      ],
      sessions: []
    });

    svc.backup.importBackupJson(legacyV1);
    expect(svc.projects.fetchAll(true)[0].name).toBe("Legado");
    expect(svc.projects.fetchById(existing.id)).toBeNull();

    const brokenDup = JSON.stringify({
      formatVersion: 2,
      exportedAt: 800000000,
      projects: [
        { id: "DUP", name: "A", client: "C", dailyRate: 0, category: "work", tags: [], descriptionText: "", status: "active", isArchived: false, isFavorite: false, createdAt: 800000000, updatedAt: 800000000 },
        { id: "DUP", name: "B", client: "C", dailyRate: 0, category: "work", tags: [], descriptionText: "", status: "active", isArchived: false, isFavorite: false, createdAt: 800000000, updatedAt: 800000000 }
      ],
      sessions: [],
      comments: [],
      reportPresets: [],
      invoices: [],
      settings: [],
      shortcuts: []
    });

    expect(() => svc.backup.importBackupJson(brokenDup)).toThrow();
    expect(svc.projects.fetchAll(true)[0].name).toBe("Legado");

    svc.db.close();
  });
});
