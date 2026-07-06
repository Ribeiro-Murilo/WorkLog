import { app, BrowserWindow, dialog, ipcMain, nativeTheme } from "electron";
import type { AppSettings, ExportFormat, ExportTable, ProjectInput, SessionInput } from "../src/shared/types";
import { BackupService } from "./services/backupService";
import { ProjectRepository } from "./services/projectRepository";
import { ReportService } from "./services/reportService";
import { SessionRepository } from "./services/sessionRepository";
import { SettingsRepository } from "./services/settingsRepository";
import { TimerService } from "./services/timerService";

export interface Services {
  projects: ProjectRepository;
  sessions: SessionRepository;
  settings: SettingsRepository;
  timer: TimerService;
  reports: ReportService;
  backup: BackupService;
}

export function registerIpc(services: Services): void {
  ipcMain.handle("app:snapshot", () => snapshot(services));

  ipcMain.handle("projects:list", (_event, includeArchived: boolean) => services.projects.fetchAll(includeArchived));
  ipcMain.handle("projects:save", (_event, id: string | null, input: ProjectInput) =>
    id ? services.projects.update(id, input) : services.projects.insert(input)
  );
  ipcMain.handle("projects:archive", (_event, id: string, archived: boolean) => services.projects.archive(id, archived));
  ipcMain.handle("projects:delete", (_event, id: string) => {
    services.projects.delete(id);
    return snapshot(services);
  });

  ipcMain.handle("sessions:list", (_event, projectId?: string | null) => services.sessions.fetchAll(projectId));
  ipcMain.handle("sessions:addManual", (_event, input: SessionInput) => services.timer.addManualSession(input));
  ipcMain.handle("sessions:updateManual", (_event, id: string, input: SessionInput) => services.timer.updateManualSession(id, input));
  ipcMain.handle("sessions:delete", (_event, id: string) => {
    services.sessions.delete(id);
    return snapshot(services);
  });

  ipcMain.handle("timer:state", () => services.timer.state());
  ipcMain.handle("timer:start", (_event, projectId: string) => services.timer.start(projectId));
  ipcMain.handle("timer:pause", () => services.timer.pause());
  ipcMain.handle("timer:resume", () => services.timer.resume());
  ipcMain.handle("timer:stop", () => services.timer.stop());

  ipcMain.handle("settings:get", () => services.settings.get());
  ipcMain.handle("settings:update", (_event, input: Partial<AppSettings>) => {
    const settings = services.settings.update(input);
    nativeTheme.themeSource = settings.theme;
    app.setLoginItemSettings({ openAtLogin: settings.launchAtLogin });
    return settings;
  });

  ipcMain.handle("backup:export", async () => {
    const result = await dialog.showSaveDialog({
      title: "Exportar backup",
      defaultPath: "worklog-backup.json",
      filters: [{ name: "JSON", extensions: ["json"] }]
    });
    if (result.canceled || !result.filePath) return null;
    return services.backup.exportBackup(result.filePath);
  });

  ipcMain.handle("backup:import", async () => {
    const result = await dialog.showOpenDialog({
      title: "Importar backup",
      filters: [{ name: "JSON", extensions: ["json"] }],
      properties: ["openFile"]
    });
    if (result.canceled || !result.filePaths[0]) return null;
    return services.backup.importBackup(result.filePaths[0]);
  });

  ipcMain.handle("export:table", async (_event, table: ExportTable, format: ExportFormat) => {
    const result = await dialog.showSaveDialog({
      title: "Exportar relatório",
      defaultPath: `${table.title}.${format === "csv" ? "csv" : "xml"}`,
      filters: [{ name: format === "csv" ? "CSV" : "Excel XML", extensions: [format === "csv" ? "csv" : "xml"] }]
    });
    if (result.canceled || !result.filePath) return false;
    services.backup.exportTable(table, format, result.filePath);
    return true;
  });
}

export function broadcastSnapshot(services: Services): void {
  const next = snapshot(services);
  for (const window of BrowserWindow.getAllWindows()) {
    window.webContents.send("app:snapshotChanged", next);
  }
}

function snapshot(services: Services) {
  return {
    projects: services.projects.fetchAll(true),
    sessions: services.sessions.fetchAll(),
    settings: services.settings.get(),
    timer: services.timer.state(),
    dashboard: services.reports.dashboardSummary()
  };
}
