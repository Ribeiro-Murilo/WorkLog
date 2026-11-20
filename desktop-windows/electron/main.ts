import { app, BrowserWindow, Menu, nativeImage, nativeTheme, Tray } from "electron";
import fs from "node:fs";
import path from "node:path";
import { formatCompactTimer } from "../src/shared/format";
import type { DashboardSection } from "../src/shared/types";
import { openDatabase } from "./data/database";
import { IdleService } from "./idleService";
import { broadcastSnapshot, registerIpc, type AppServices } from "./ipc";
import { NotchController } from "./notchController";
import { BackupService } from "./services/backupService";
import { BillingService } from "./services/billingService";
import { CommentRepository } from "./services/commentRepository";
import { DashboardService } from "./services/dashboardService";
import { InvoiceRepository } from "./services/invoiceRepository";
import { ProjectRepository } from "./services/projectRepository";
import { ReportPresetRepository } from "./services/reportPresetRepository";
import { ReportService } from "./services/reportService";
import { SessionRepository } from "./services/sessionRepository";
import { SettingsRepository } from "./services/settingsRepository";
import { ShortcutRepository } from "./services/shortcutRepository";
import { TimerService } from "./services/timerService";
import { ShortcutsService } from "./shortcutsService";

let dashboardWindow: BrowserWindow | null = null;
let tray: Tray | null = null;
let services: AppServices;
let isQuitting = false;
let dbHandle: ReturnType<typeof openDatabase> | null = null;

const gotLock = app.requestSingleInstanceLock();
if (!gotLock) {
  app.quit();
}

app.on("second-instance", () => {
  if (services) {
    services.openDashboard();
  }
});

app.whenReady().then(() => {
  const dbPath = path.join(app.getPath("userData"), "worklog.sqlite");
  dbHandle = openDatabase(dbPath);

  const projects = new ProjectRepository(dbHandle);
  const sessions = new SessionRepository(dbHandle);
  const comments = new CommentRepository(dbHandle);
  const presets = new ReportPresetRepository(dbHandle);
  const settingsRepo = new SettingsRepository(dbHandle);
  const invoices = new InvoiceRepository(dbHandle, settingsRepo);
  const shortcutsRepo = new ShortcutRepository(dbHandle);

  const initialSettings = settingsRepo.current();
  nativeTheme.themeSource = initialSettings.theme;
  if (app.isPackaged) {
    try {
      app.setLoginItemSettings({ openAtLogin: initialSettings.launchAtLogin });
    } catch {
      // Ignora em ambientes sem suporte.
    }
  }

  const preloadPath = path.join(__dirname, "preload.js");

  const notch = new NotchController({
    preloadPath,
    onStateChanged: () => {
      if (services) {
        updateTray();
        broadcastSnapshot(services);
      }
    }
  });

  const timer = new TimerService(sessions, projects, () => {
    if (services) {
      services.notch.setRunningState(services.timer.isRunning());
      updateTray();
      broadcastSnapshot(services);
    }
  });

  const dashboard = new DashboardService(projects, sessions);
  const reports = new ReportService(projects, sessions, settingsRepo);
  const billing = new BillingService(projects, sessions, invoices, settingsRepo);
  const backup = new BackupService(
    dbHandle,
    projects,
    sessions,
    comments,
    presets,
    invoices,
    settingsRepo,
    shortcutsRepo
  );

  const idle = new IdleService(initialSettings.idleTimeoutMinutes, () => {
    if (services && services.timer.isRunning()) {
      services.timer.pause();
      services.notch.setRunningState(false);
      updateTray();
      broadcastSnapshot(services);
    }
  });

  const shortcuts = new ShortcutsService(shortcutsRepo, {
    startTimer: () => {
      services.timer.resume(null);
      services.notch.setRunningState(services.timer.isRunning());
      updateTray();
      broadcastSnapshot(services);
    },
    pauseTimer: () => {
      services.timer.pause();
      services.notch.setRunningState(false);
      updateTray();
      broadcastSnapshot(services);
    },
    openDashboard: () => toggleDashboardWindow(),
    openPopover: () => {
      if (services.settings.current().displayMode === "notch") {
        services.notch.toggleExpand();
      } else {
        toggleDashboardWindow();
      }
    },
    searchProject: () => openDashboard("projects", { focusSearch: true }),
    newProject: () => openDashboard("projects", { openNewProject: true })
  });

  services = {
    projects,
    sessions,
    comments,
    presets,
    invoices,
    settings: settingsRepo,
    shortcutsRepo,
    timer,
    dashboard,
    reports,
    billing,
    backup,
    notch,
    idle,
    shortcuts,
    getDashboardWindow: () => dashboardWindow,
    openDashboard,
    applyDisplayMode,
    getLogoDataUrl: loadLogoDataUrl,
    quitApp
  };

  registerIpc(services);
  createTray();
  shortcuts.registerAll();
  idle.start();
  applyDisplayMode();

  // Em primeira execução sem projetos ou se o usuário abrir em modo tray, abre o Dashboard
  if (projects.fetchAll(true).length === 0 || initialSettings.displayMode === "menuBar") {
    openDashboard("summary");
  }
});

app.on("window-all-closed", () => {
  // Mantém o app ativo em segundo plano (Notch + Bandeja do sistema).
});

app.on("before-quit", () => {
  isQuitting = true;
  if (services) {
    services.shortcuts.unregisterAll();
    services.idle.stop();
    services.timer.dispose();
    services.notch.destroy();
  }
  if (dbHandle) {
    try {
      dbHandle.close();
    } catch {
      // ignora
    }
    dbHandle = null;
  }
});

function resolveAssetPath(fileName: string): string | null {
  const candidates = [
    path.join(__dirname, "../../assets", fileName),
    path.join(process.resourcesPath, "assets", fileName),
    path.join(process.resourcesPath, "app.asar.unpacked/assets", fileName),
    path.join(process.resourcesPath, "app.asar/assets", fileName)
  ];
  return candidates.find((candidate) => fs.existsSync(candidate)) ?? null;
}

function loadLogoDataUrl(): string | null {
  const logoPath = resolveAssetPath("icon.png");
  if (!logoPath) return null;
  try {
    const buf = fs.readFileSync(logoPath);
    return `data:image/png;base64,${buf.toString("base64")}`;
  } catch {
    return null;
  }
}

function createDashboardWindow(
  initialSection?: DashboardSection,
  options?: { focusSearch?: boolean; openNewProject?: boolean }
): BrowserWindow {
  const iconPath = resolveAssetPath("icon.png");
  const win = new BrowserWindow({
    width: 1120,
    height: 740,
    minWidth: 880,
    minHeight: 560,
    title: "WorkLog",
    show: false,
    autoHideMenuBar: true,
    icon: iconPath ?? undefined,
    webPreferences: {
      preload: path.join(__dirname, "preload.js"),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: false
    }
  });

  win.on("close", (event) => {
    if (!isQuitting) {
      event.preventDefault();
      win.hide();
    }
  });

  const query: Record<string, string> = {};
  if (initialSection) query.section = initialSection;
  if (options?.focusSearch) query.focusSearch = "1";
  if (options?.openNewProject) query.openNewProject = "1";

  if (process.env.VITE_DEV_SERVER_URL) {
    const url = new URL(process.env.VITE_DEV_SERVER_URL);
    for (const [k, v] of Object.entries(query)) url.searchParams.set(k, v);
    void win.loadURL(url.toString());
  } else {
    void win.loadFile(path.join(__dirname, "../../dist/index.html"), { query });
  }

  return win;
}

function openDashboard(
  section?: DashboardSection,
  options?: { focusSearch?: boolean; openNewProject?: boolean }
): void {
  if (!dashboardWindow || dashboardWindow.isDestroyed()) {
    dashboardWindow = createDashboardWindow(section, options);
    dashboardWindow.once("ready-to-show", () => {
      dashboardWindow?.show();
      dashboardWindow?.focus();
    });
    return;
  }

  if (dashboardWindow.isMinimized()) dashboardWindow.restore();
  dashboardWindow.show();
  dashboardWindow.focus();
  if (section) {
    dashboardWindow.webContents.send("app:navigate", {
      section,
      focusSearch: options?.focusSearch,
      openNewProject: options?.openNewProject
    });
  }
}

function toggleDashboardWindow(): void {
  if (dashboardWindow && !dashboardWindow.isDestroyed() && dashboardWindow.isVisible() && dashboardWindow.isFocused()) {
    dashboardWindow.hide();
  } else {
    openDashboard();
  }
}

function applyDisplayMode(): void {
  if (!services) return;
  const current = services.settings.current();
  services.notch.setRunningState(services.timer.isRunning());
  if (current.displayMode === "notch") {
    services.notch.present(current.notchDisplayId);
  } else {
    services.notch.dismiss();
  }
  updateTray();
}

function createTray(): void {
  const iconPath = resolveAssetPath("icon.png");
  const icon = iconPath
    ? nativeImage.createFromPath(iconPath).resize({ width: 16, height: 16 })
    : nativeImage.createEmpty();
  tray = new Tray(icon);
  tray.setToolTip("WorkLog");
  tray.on("click", () => {
    openDashboard();
  });
  updateTray();
}

function updateTray(): void {
  if (!tray || !services) return;
  const timerState = services.timer.state();
  const settings = services.settings.current();
  const notchState = services.notch.state;

  const statusText = timerState.activeProject
    ? `${timerState.activeProject.name} • ${formatCompactTimer(timerState.elapsedSeconds, settings.showSeconds)}`
    : timerState.resumableProject
      ? `Pausado: ${timerState.resumableProject.name}`
      : "Sem timer ativo";

  tray.setToolTip(`WorkLog — ${statusText}`);

  const menuTemplate: Electron.MenuItemConstructorOptions[] = [
    { label: statusText, enabled: false },
    { type: "separator" },
    { label: "Abrir Dashboard", click: () => openDashboard("summary") },
    {
      label: notchState.isExpanded ? "Recolher barra superior" : "Expandir barra superior",
      visible: settings.displayMode === "notch",
      click: () => services.notch.toggleExpand()
    },
    { type: "separator" },
    {
      label: "Pausar",
      enabled: timerState.isRunning,
      click: () => {
        services.timer.pause();
        services.notch.setRunningState(false);
        updateTray();
        broadcastSnapshot(services);
      }
    },
    {
      label: "Retomar último",
      enabled: !timerState.isRunning && timerState.resumableSession !== null,
      click: () => {
        services.timer.resume(null);
        services.notch.setRunningState(services.timer.isRunning());
        updateTray();
        broadcastSnapshot(services);
      }
    },
    {
      label: "Encerrar",
      enabled: timerState.isRunning,
      click: () => {
        services.timer.stop();
        services.notch.setRunningState(false);
        updateTray();
        broadcastSnapshot(services);
      }
    },
    { type: "separator" },
    { label: "Configurações", click: () => openDashboard("settings") },
    { label: "Sair do WorkLog", click: () => quitApp() }
  ];

  tray.setContextMenu(Menu.buildFromTemplate(menuTemplate));
}

function quitApp(): void {
  isQuitting = true;
  app.quit();
}
