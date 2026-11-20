import { app, BrowserWindow, dialog, ipcMain, nativeTheme } from "electron";
import fs from "node:fs";
import os from "node:os";
import { formatCompactTimer, projectColorHex } from "../src/shared/format";
import type {
  AppSettings,
  AppSnapshot,
  Comment,
  DashboardSection,
  ExportFormat,
  ProjectInput,
  ReportColumn,
  ReportFilter,
  ReportGrouping,
  ReportPeriod,
  SessionUpdateInput,
  SessionWorkPeriod,
  ShortcutAction
} from "../src/shared/types";
import type { IdleService } from "./idleService";
import type { NotchController } from "./notchController";
import { renderHtmlToPdf } from "./pdfExporter";
import type { BackupService } from "./services/backupService";
import type { BillingService } from "./services/billingService";
import type { CommentRepository } from "./services/commentRepository";
import type { DashboardService } from "./services/dashboardService";
import type { InvoiceRepository } from "./services/invoiceRepository";
import type { ProjectRepository } from "./services/projectRepository";
import type { ReportPresetRepository } from "./services/reportPresetRepository";
import type { ReportService } from "./services/reportService";
import type { SessionRepository } from "./services/sessionRepository";
import type { SettingsRepository } from "./services/settingsRepository";
import type { ShortcutRepository } from "./services/shortcutRepository";
import type { TimerService } from "./services/timerService";
import type { ShortcutsService } from "./shortcutsService";

export interface AppServices {
  projects: ProjectRepository;
  sessions: SessionRepository;
  comments: CommentRepository;
  presets: ReportPresetRepository;
  invoices: InvoiceRepository;
  settings: SettingsRepository;
  shortcutsRepo: ShortcutRepository;
  timer: TimerService;
  dashboard: DashboardService;
  reports: ReportService;
  billing: BillingService;
  backup: BackupService;
  notch: NotchController;
  idle: IdleService;
  shortcuts: ShortcutsService;
  getDashboardWindow: () => BrowserWindow | null;
  openDashboard: (section?: DashboardSection, options?: { focusSearch?: boolean; openNewProject?: boolean }) => void;
  applyDisplayMode: () => void;
  getLogoDataUrl: () => string | null;
  quitApp: () => void;
}

export function buildSnapshot(services: AppServices): AppSnapshot {
  const allProjects = services.projects.fetchAll(true);
  const projectsById = new Map(allProjects.map((p) => [p.id, p]));
  const allSessions = services.sessions.fetchAll(null);
  const enrichedProjects = services.dashboard.enrichProjects(allProjects, allSessions);
  const enrichedSessions = services.dashboard.enrichSessions(allSessions, projectsById);
  const recentSessions = enrichedSessions.slice(0, 10);

  const allComments = services.comments.fetchAll();
  const commentsByProject: Record<string, Comment[]> = {};
  for (const comment of allComments) {
    if (!comment.projectId) continue;
    const list = commentsByProject[comment.projectId] ?? [];
    list.push(comment);
    commentsByProject[comment.projectId] = list;
  }

  const settings = services.settings.current();
  const timerState = services.timer.state();
  const notchState = services.notch.state;

  const compactElapsed = timerState.isRunning
    ? formatCompactTimer(timerState.elapsedSeconds, settings.showSeconds)
    : null;
  const activeProjectColor = timerState.activeProject
    ? projectColorHex(timerState.activeProject.id)
    : timerState.resumableProject
      ? projectColorHex(timerState.resumableProject.id)
      : null;

  return {
    projects: enrichedProjects,
    sessions: enrichedSessions,
    recentSessions,
    commentsByProject,
    presets: services.presets.fetchAll(),
    invoices: services.invoices.fetchAll(),
    settings,
    shortcuts: services.shortcutsRepo.ensureDefaults(),
    timer: timerState,
    dashboard: services.dashboard.summary(),
    displays: services.notch.getDisplays(),
    notch: {
      isExpanded: notchState.isExpanded,
      isPinned: notchState.isPinned,
      isRunning: timerState.isRunning,
      compactElapsed,
      activeProjectColor
    },
    appVersion: app.getVersion()
  };
}

export function broadcastSnapshot(services: AppServices): void {
  const snapshot = buildSnapshot(services);
  const dashboardWin = services.getDashboardWindow();
  if (dashboardWin && !dashboardWin.isDestroyed()) {
    dashboardWin.webContents.send("app:snapshot", snapshot);
  }
  const notchWin = services.notch.getWindow();
  if (notchWin && !notchWin.isDestroyed()) {
    notchWin.webContents.send("app:snapshot", snapshot);
  }
}

export function registerIpc(services: AppServices): void {
  const notify = () => {
    services.notch.setRunningState(services.timer.isRunning());
    broadcastSnapshot(services);
  };

  ipcMain.handle("app:getSnapshot", () => buildSnapshot(services));

  ipcMain.handle("timer:start", (_e, projectId: string) => {
    services.timer.start(projectId);
    notify();
  });
  ipcMain.handle("timer:pause", () => {
    services.timer.pause();
    notify();
  });
  ipcMain.handle("timer:resume", (_e, projectId?: string | null) => {
    services.timer.resume(projectId ?? null);
    notify();
  });
  ipcMain.handle("timer:stop", () => {
    services.timer.stop();
    notify();
  });

  ipcMain.handle("projects:create", (_e, input: ProjectInput) => {
    services.projects.insert(input);
    notify();
  });
  ipcMain.handle("projects:update", (_e, id: string, input: ProjectInput) => {
    services.projects.update(id, input);
    notify();
  });
  ipcMain.handle("projects:delete", (_e, id: string) => {
    const active = services.timer.state().activeSession;
    if (active && active.projectId === id) {
      services.timer.stop();
    }
    services.projects.delete(id);
    notify();
  });
  ipcMain.handle("projects:archive", (_e, id: string, archived: boolean) => {
    services.projects.archive(id, archived);
    notify();
  });
  ipcMain.handle("projects:toggleFavorite", (_e, id: string) => {
    services.projects.toggleFavorite(id);
    notify();
  });

  ipcMain.handle("comments:add", (_e, projectId: string, text: string) => {
    const trimmed = text.trim();
    if (!trimmed) return;
    const author = os.userInfo().username || "Usuário";
    services.comments.insert({ projectId, text: trimmed, author });
    notify();
  });
  ipcMain.handle("comments:delete", (_e, id: string) => {
    services.comments.delete(id);
    notify();
  });

  ipcMain.handle(
    "sessions:addManual",
    (_e, input: { projectId: string; startTime: string; endTime: string; note: string }) => {
      services.timer.addManualSession(input);
      notify();
    }
  );
  ipcMain.handle("sessions:update", (_e, sessionId: string, input: SessionUpdateInput) => {
    services.timer.updateSession(sessionId, input);
    notify();
  });
  ipcMain.handle("sessions:delete", (_e, sessionId: string) => {
    services.sessions.delete(sessionId);
    notify();
  });
  ipcMain.handle(
    "sessions:checkAvailability",
    (
      _e,
      params: {
        startTime: string;
        endTime: string;
        excludingSessionId?: string | null;
        workPeriods?: SessionWorkPeriod[];
      }
    ) => services.timer.checkAvailability(params)
  );

  const showSave = (options: Electron.SaveDialogOptions) => {
    const owner = services.getDashboardWindow();
    return owner && !owner.isDestroyed()
      ? dialog.showSaveDialog(owner, options)
      : dialog.showSaveDialog(options);
  };

  const showOpen = (options: Electron.OpenDialogOptions) => {
    const owner = services.getDashboardWindow();
    return owner && !owner.isDestroyed()
      ? dialog.showOpenDialog(owner, options)
      : dialog.showOpenDialog(options);
  };

  ipcMain.handle("reports:generate", (_e, filter: ReportFilter) => services.reports.generate(filter));
  ipcMain.handle("reports:export", async (_e, filter: ReportFilter, format: ExportFormat) => {
    const ext = format === "excel" ? "xml" : format;
    const filterName =
      format === "csv" ? "CSV" : format === "excel" ? "Excel XML" : "PDF";
    const result = await showSave({
      title: `Exportar relatório (${filterName})`,
      defaultPath: `Relatorio.${ext}`,
      filters: [{ name: filterName, extensions: [ext] }]
    });
    if (result.canceled || !result.filePath) {
      return { saved: false };
    }
    const payloads = services.reports.buildExportPayloads(filter, services.getLogoDataUrl());
    if (format === "csv") {
      fs.writeFileSync(result.filePath, payloads.csv, "utf8");
    } else if (format === "excel") {
      fs.writeFileSync(result.filePath, payloads.excelXml, "utf8");
    } else {
      await renderHtmlToPdf(payloads.pdfHtml, result.filePath);
    }
    return { saved: true, filePath: result.filePath };
  });
  ipcMain.handle(
    "reports:savePreset",
    (_e, name: string, columns: ReportColumn[], grouping: ReportGrouping) => {
      services.presets.upsertByName(name, columns, grouping);
      notify();
    }
  );
  ipcMain.handle("reports:deletePreset", (_e, id: string) => {
    services.presets.delete(id);
    notify();
  });

  ipcMain.handle("billing:availableClients", () => services.billing.availableClients());
  ipcMain.handle(
    "billing:preview",
    (_e, params: { client: string | null; period: ReportPeriod; customStart: string; customEnd: string }) =>
      services.billing.preview(params)
  );
  ipcMain.handle(
    "billing:generateInvoice",
    (
      _e,
      params: { client: string; period: ReportPeriod; customStart: string; customEnd: string; notes: string }
    ) => {
      services.billing.generateInvoice(params);
      notify();
    }
  );
  ipcMain.handle("billing:toggleStatus", (_e, invoiceId: string) => {
    services.billing.toggleStatus(invoiceId);
    notify();
  });
  ipcMain.handle("billing:deleteInvoice", (_e, invoiceId: string) => {
    services.billing.deleteInvoice(invoiceId);
    notify();
  });
  ipcMain.handle("billing:exportPdf", async (_e, invoiceId: string) => {
    const invoice = services.invoices.fetchById(invoiceId);
    if (!invoice) throw new Error("Fatura não encontrada.");
    const result = await showSave({
      title: `Exportar ${invoice.formattedNumber}`,
      defaultPath: `${invoice.formattedNumber}.pdf`,
      filters: [{ name: "PDF", extensions: ["pdf"] }]
    });
    if (result.canceled || !result.filePath) {
      return { saved: false };
    }
    const html = services.billing.buildInvoicePdfHtml(invoiceId, services.getLogoDataUrl());
    await renderHtmlToPdf(html, result.filePath);
    return { saved: true, filePath: result.filePath };
  });

  ipcMain.handle("settings:save", (_e, patch: Partial<AppSettings>) => {
    const updated = services.settings.save(patch);
    nativeTheme.themeSource = updated.theme;
    services.idle.updateThreshold(updated.idleTimeoutMinutes);
    if (app.isPackaged) {
      try {
        app.setLoginItemSettings({ openAtLogin: updated.launchAtLogin });
      } catch {
        // Ignora se plataforma/sandbox não suportar login item.
      }
    }
    services.applyDisplayMode();
    notify();
  });

  ipcMain.handle("settings:updateShortcut", (_e, action: ShortcutAction, accelerator: string) => {
    services.shortcuts.updateBinding(action, accelerator, true);
    notify();
  });

  ipcMain.handle("backup:exportJson", async () => {
    const result = await showSave({
      title: "Exportar backup",
      defaultPath: "WorkLog-Backup.json",
      filters: [{ name: "JSON", extensions: ["json"] }]
    });
    if (result.canceled || !result.filePath) {
      return { saved: false };
    }
    const json = services.backup.exportBackupJson();
    fs.writeFileSync(result.filePath, json, "utf8");
    notify();
    return { saved: true, filePath: result.filePath };
  });

  ipcMain.handle("backup:importJson", async () => {
    const result = await showOpen({
      title: "Importar backup",
      properties: ["openFile"],
      filters: [{ name: "JSON", extensions: ["json"] }]
    });
    if (result.canceled || result.filePaths.length === 0) {
      return { imported: false };
    }
    try {
      const content = fs.readFileSync(result.filePaths[0], "utf8");
      services.backup.importBackupJson(content);
      const updated = services.settings.current();
      nativeTheme.themeSource = updated.theme;
      services.idle.updateThreshold(updated.idleTimeoutMinutes);
      services.shortcuts.registerAll();
      services.applyDisplayMode();
      notify();
      return { imported: true };
    } catch (error) {
      return {
        imported: false,
        error: error instanceof Error ? error.message : String(error)
      };
    }
  });

  ipcMain.handle("notch:setPinned", (_e, pinned: boolean) => {
    services.notch.setPinned(pinned);
  });
  ipcMain.handle("notch:setExpandedHeight", (_e, height: number) => {
    services.notch.setExpandedHeight(height);
  });
  ipcMain.handle("notch:setEditing", (_e, editing: boolean) => {
    services.notch.setEditing(editing);
  });
  ipcMain.handle("notch:setMenuOpen", (_e, open: boolean) => {
    services.notch.setMenuOpen(open);
  });
  ipcMain.handle("notch:expand", () => {
    services.notch.expandNow(false);
  });
  ipcMain.handle("notch:collapse", () => {
    services.notch.collapseNow();
  });

  ipcMain.handle("app:openDashboard", (_e, section?: DashboardSection) => {
    services.openDashboard(section);
  });
  ipcMain.handle("app:quit", () => {
    services.quitApp();
  });
}
