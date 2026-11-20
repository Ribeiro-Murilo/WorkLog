import { BrowserWindow, screen, type Display } from "electron";
import path from "node:path";
import {
  WINDOWS_NOTCH_METRICS,
  computeNotchRects,
  pointInRect,
  shouldExpandNotch
} from "../src/shared/notchGeometry";
import type { DisplayInfo } from "../src/shared/types";

export interface NotchControllerOptions {
  preloadPath: string;
  onStateChanged: () => void;
}

export class NotchController {
  private win: BrowserWindow | null = null;
  private pollTimer: NodeJS.Timeout | null = null;
  private collapseTimeout: NodeJS.Timeout | null = null;

  private isPresented = false;
  private isExpanded = false;
  private isPinned = false;
  private isRunning = false;
  private isEditing = false;
  private isMenuOpen = false;
  private measuredExpandedHeight = 360;
  private preferredDisplayId: string | null = null;
  private lastIgnoreMouse: boolean | null = null;

  private readonly displayListener = () => {
    if (this.isPresented) {
      this.reposition();
    }
  };

  constructor(private readonly options: NotchControllerOptions) {
    screen.on("display-metrics-changed", this.displayListener);
    screen.on("display-added", this.displayListener);
    screen.on("display-removed", this.displayListener);
  }

  get state(): { isExpanded: boolean; isPinned: boolean; isPresented: boolean } {
    return {
      isExpanded: this.isExpanded,
      isPinned: this.isPinned,
      isPresented: this.isPresented
    };
  }

  getDisplays(): DisplayInfo[] {
    const primaryId = String(screen.getPrimaryDisplay().id);
    return screen.getAllDisplays().map((d, index) => ({
      id: String(d.id),
      label: d.label
        ? `${d.label}${String(d.id) === primaryId ? " (Principal)" : ""}`
        : `Monitor ${index + 1}${String(d.id) === primaryId ? " (Principal)" : ""}`,
      isPrimary: String(d.id) === primaryId,
      bounds: { ...d.bounds }
    }));
  }

  present(displayId: string | null): void {
    this.preferredDisplayId = displayId;
    if (!this.win || this.win.isDestroyed()) {
      this.createWindow();
    }
    this.isPresented = true;
    this.reposition();
    if (this.win && !this.win.isDestroyed()) {
      this.win.setAlwaysOnTop(true, "screen-saver", 1);
      this.win.showInactive();
      this.win.moveTop();
    }
    this.startPolling();
  }

  dismiss(): void {
    this.stopPolling();
    this.clearCollapseTimer();
    this.isPresented = false;
    this.isExpanded = false;
    this.isPinned = false;
    this.isEditing = false;
    this.isMenuOpen = false;
    this.lastIgnoreMouse = null;
    if (this.win && !this.win.isDestroyed()) {
      this.win.hide();
    }
    this.options.onStateChanged();
  }

  destroy(): void {
    this.stopPolling();
    this.clearCollapseTimer();
    screen.off("display-metrics-changed", this.displayListener);
    screen.off("display-added", this.displayListener);
    screen.off("display-removed", this.displayListener);
    if (this.win && !this.win.isDestroyed()) {
      this.win.destroy();
    }
    this.win = null;
  }

  setRunningState(isRunning: boolean): void {
    if (this.isRunning === isRunning) return;
    this.isRunning = isRunning;
    this.evaluateCursor();
  }

  setExpandedHeight(height: number): void {
    if (!Number.isFinite(height) || height <= 0) return;
    const clamped = Math.min(Math.ceil(height), WINDOWS_NOTCH_METRICS.defaultWindowHeight);
    if (Math.abs(this.measuredExpandedHeight - clamped) < 1) return;
    this.measuredExpandedHeight = clamped;
    this.evaluateCursor();
  }

  setPinned(pinned: boolean): void {
    if (this.isPinned === pinned) return;
    this.isPinned = pinned;
    if (pinned && !this.isExpanded) {
      this.setExpanded(true);
    } else {
      this.options.onStateChanged();
    }
  }

  setEditing(editing: boolean): void {
    this.isEditing = editing;
  }

  setMenuOpen(open: boolean): void {
    this.isMenuOpen = open;
  }

  expandNow(pin = false): void {
    if (!this.isPresented) return;
    if (pin) this.isPinned = true;
    this.clearCollapseTimer();
    this.setExpanded(true);
  }

  collapseNow(): void {
    this.clearCollapseTimer();
    this.isPinned = false;
    this.isEditing = false;
    this.isMenuOpen = false;
    this.setExpanded(false);
  }

  toggleExpand(): void {
    if (!this.isPresented) return;
    if (this.isExpanded) {
      this.collapseNow();
    } else {
      this.expandNow(true);
    }
  }

  getWindow(): BrowserWindow | null {
    return this.win && !this.win.isDestroyed() ? this.win : null;
  }

  reposition(): void {
    if (!this.win || this.win.isDestroyed()) return;
    const display = this.resolveDisplay();
    const rects = computeNotchRects(display.bounds, this.isRunning, this.measuredExpandedHeight);
    this.win.setBounds(rects.windowBounds, false);
  }

  private resolveDisplay(): Display {
    const displays = screen.getAllDisplays();
    if (this.preferredDisplayId) {
      const match = displays.find((d) => String(d.id) === this.preferredDisplayId);
      if (match) return match;
    }
    return screen.getPrimaryDisplay();
  }

  private createWindow(): void {
    const display = this.resolveDisplay();
    const rects = computeNotchRects(display.bounds, this.isRunning, this.measuredExpandedHeight);

    const win = new BrowserWindow({
      ...rects.windowBounds,
      frame: false,
      transparent: true,
      backgroundColor: "#00000000",
      hasShadow: false,
      resizable: false,
      movable: false,
      minimizable: false,
      maximizable: false,
      fullscreenable: false,
      skipTaskbar: true,
      alwaysOnTop: true,
      focusable: true,
      show: false,
      webPreferences: {
        preload: this.options.preloadPath,
        contextIsolation: true,
        nodeIntegration: false,
        sandbox: false
      }
    });

    win.setAlwaysOnTop(true, "screen-saver", 1);
    win.setVisibleOnAllWorkspaces(true, { visibleOnFullScreen: true });
    win.setIgnoreMouseEvents(true);
    this.lastIgnoreMouse = true;

    if (process.env.VITE_DEV_SERVER_URL) {
      const base = process.env.VITE_DEV_SERVER_URL.replace(/\/$/, "");
      void win.loadURL(`${base}/#/notch`);
    } else {
      void win.loadFile(path.join(__dirname, "../../dist/index.html"), {
        hash: "notch"
      });
    }

    win.webContents.once("did-finish-load", () => {
      this.options.onStateChanged();
    });

    this.win = win;
  }

  private startPolling(): void {
    this.stopPolling();
    this.pollTimer = setInterval(() => {
      this.evaluateCursor();
    }, 60);
  }

  private stopPolling(): void {
    if (this.pollTimer) {
      clearInterval(this.pollTimer);
      this.pollTimer = null;
    }
  }

  private clearCollapseTimer(): void {
    if (this.collapseTimeout) {
      clearTimeout(this.collapseTimeout);
      this.collapseTimeout = null;
    }
  }

  private evaluateCursor(): void {
    if (!this.isPresented || !this.win || this.win.isDestroyed()) return;

    const display = this.resolveDisplay();
    const rects = computeNotchRects(display.bounds, this.isRunning, this.measuredExpandedHeight);
    const cursor = screen.getCursorScreenPoint();

    const inCollapsed = pointInRect(cursor, rects.collapsedRect);
    const inExpanded = pointInRect(cursor, rects.expandedRect);
    const activeRect = this.isExpanded ? rects.expandedRect : rects.collapsedRect;
    const isInsideInteractive = pointInRect(cursor, activeRect);

    const ignoreMouse = !isInsideInteractive;
    if (this.lastIgnoreMouse !== ignoreMouse) {
      this.lastIgnoreMouse = ignoreMouse;
      this.win.setIgnoreMouseEvents(ignoreMouse);
    }

    const wantExpanded = shouldExpandNotch({
      isExpanded: this.isExpanded,
      isPinned: this.isPinned,
      isEditing: this.isEditing,
      isMenuOpen: this.isMenuOpen,
      containsExpanded: inExpanded,
      containsCollapsed: inCollapsed
    });

    if (!this.isExpanded && wantExpanded) {
      this.clearCollapseTimer();
      this.setExpanded(true);
    } else if (this.isExpanded && wantExpanded) {
      this.clearCollapseTimer();
    } else if (this.isExpanded && !wantExpanded && !this.collapseTimeout) {
      this.collapseTimeout = setTimeout(() => {
        this.collapseTimeout = null;
        this.setExpanded(false);
      }, 160);
    }
  }

  private setExpanded(expanded: boolean): void {
    if (this.isExpanded === expanded) return;
    this.isExpanded = expanded;

    if (!expanded && this.win && !this.win.isDestroyed() && this.win.isFocused()) {
      this.win.blur();
    }

    if (this.win && !this.win.isDestroyed()) {
      const display = this.resolveDisplay();
      const rects = computeNotchRects(display.bounds, this.isRunning, this.measuredExpandedHeight);
      const cursor = screen.getCursorScreenPoint();
      const activeRect = expanded ? rects.expandedRect : rects.collapsedRect;
      const ignore = !pointInRect(cursor, activeRect);
      this.lastIgnoreMouse = ignore;
      this.win.setIgnoreMouseEvents(ignore);
    }

    this.options.onStateChanged();
  }
}
