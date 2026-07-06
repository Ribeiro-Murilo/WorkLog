import { app, BrowserWindow, globalShortcut, Menu, nativeImage, nativeTheme, Tray } from "electron";
import path from "node:path";
import { getDatabase, closeDatabase } from "./data/database";
import { BackupService } from "./services/backupService";
import { ProjectRepository } from "./services/projectRepository";
import { ReportService } from "./services/reportService";
import { SessionRepository } from "./services/sessionRepository";
import { SettingsRepository } from "./services/settingsRepository";
import { TimerService } from "./services/timerService";
import { broadcastSnapshot, registerIpc, type Services } from "./ipc";

let mainWindow: BrowserWindow | null = null;
let tray: Tray | null = null;
let services: Services;
let isQuitting = false;

const gotLock = app.requestSingleInstanceLock();
if (!gotLock) {
  app.quit();
}

app.on("second-instance", () => {
  showMainWindow();
});

app.whenReady().then(() => {
  return getDatabase();
}).then((db) => {
  const projects = new ProjectRepository(db);
  const sessions = new SessionRepository(db);
  const settings = new SettingsRepository(db);
  const timer = new TimerService(projects, sessions, settings, () => {
    updateTray();
    broadcastSnapshot(services);
  });
  const reports = new ReportService(projects, sessions);
  const backup = new BackupService(projects, sessions, settings);
  services = { projects, sessions, settings, timer, reports, backup };

  nativeTheme.themeSource = settings.get().theme;
  app.setLoginItemSettings({ openAtLogin: settings.get().launchAtLogin });

  registerIpc(services);
  createWindow();
  createTray();
  registerShortcuts();
});

app.on("activate", () => {
  if (BrowserWindow.getAllWindows().length === 0) createWindow();
});

app.on("window-all-closed", () => {
  mainWindow?.hide();
});

app.on("before-quit", () => {
  globalShortcut.unregisterAll();
  closeDatabase();
});

function createWindow(): void {
  mainWindow = new BrowserWindow({
    width: 1180,
    height: 760,
    minWidth: 980,
    minHeight: 640,
    title: "WorkLog",
    show: false,
    webPreferences: {
      preload: path.join(__dirname, "preload.js"),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: false
    }
  });

  services.timer.registerWindow(mainWindow);
  mainWindow.once("ready-to-show", () => mainWindow?.show());
  mainWindow.on("close", (event) => {
    if (!isQuitting) {
      event.preventDefault();
      mainWindow?.hide();
    }
  });

  if (process.env.VITE_DEV_SERVER_URL) {
    mainWindow.loadURL(process.env.VITE_DEV_SERVER_URL);
  } else {
    mainWindow.loadFile(path.join(__dirname, "../../dist/index.html"));
  }
}

function showMainWindow(): void {
  if (!mainWindow) createWindow();
  mainWindow?.show();
  mainWindow?.focus();
}

function createTray(): void {
  const icon = nativeImage.createFromNamedImage("NSTouchBarHistoryTemplate") || nativeImage.createEmpty();
  tray = new Tray(icon.resize({ width: 16, height: 16 }));
  tray.setToolTip("WorkLog");
  tray.on("click", showMainWindow);
  updateTray();
}

function updateTray(): void {
  if (!tray || !services) return;
  const state = services.timer.state();
  const activeLabel = state.activeProject ? `${state.activeProject.name} - ${formatTrayTime(state.elapsedSeconds)}` : "Sem timer ativo";
  tray.setTitle(process.platform === "darwin" && state.activeProject ? activeLabel : "");
  tray.setContextMenu(
    Menu.buildFromTemplate([
      { label: activeLabel, enabled: false },
      { type: "separator" },
      { label: "Abrir WorkLog", click: showMainWindow },
      { label: "Pausar", enabled: state.isRunning, click: () => services.timer.pause() },
      { label: "Continuar ultimo", click: () => services.timer.resume() },
      { label: "Encerrar", enabled: state.isRunning, click: () => services.timer.stop() },
      { type: "separator" },
      { label: "Sair", click: () => quitApp() }
    ])
  );
}

function registerShortcuts(): void {
  globalShortcut.register("CommandOrControl+Shift+Space", showMainWindow);
  globalShortcut.register("CommandOrControl+Shift+P", () => services.timer.pause());
}

function quitApp(): void {
  isQuitting = true;
  app.quit();
}

function formatTrayTime(seconds: number): string {
  const hours = Math.floor(seconds / 3600);
  const minutes = Math.floor((seconds % 3600) / 60);
  return `${String(hours).padStart(2, "0")}:${String(minutes).padStart(2, "0")}`;
}
