import { contextBridge, ipcRenderer } from "electron";
import type {
  AppSettings,
  BackupPayload,
  DashboardSummary,
  ExportFormat,
  ExportTable,
  Project,
  ProjectInput,
  Session,
  SessionInput,
  TimerState
} from "../src/shared/types";

export interface AppSnapshot {
  projects: Project[];
  sessions: Session[];
  settings: AppSettings;
  timer: TimerState;
  dashboard: DashboardSummary;
}

const api = {
  snapshot: () => ipcRenderer.invoke("app:snapshot") as Promise<AppSnapshot>,
  onSnapshotChanged: (callback: (snapshot: AppSnapshot) => void) => {
    const listener = (_event: Electron.IpcRendererEvent, snapshot: AppSnapshot) => callback(snapshot);
    ipcRenderer.on("app:snapshotChanged", listener);
    return () => ipcRenderer.off("app:snapshotChanged", listener);
  },
  projects: {
    list: (includeArchived = true) => ipcRenderer.invoke("projects:list", includeArchived) as Promise<Project[]>,
    save: (id: string | null, input: ProjectInput) => ipcRenderer.invoke("projects:save", id, input) as Promise<Project>,
    archive: (id: string, archived: boolean) => ipcRenderer.invoke("projects:archive", id, archived) as Promise<Project>,
    delete: (id: string) => ipcRenderer.invoke("projects:delete", id) as Promise<AppSnapshot>
  },
  sessions: {
    list: (projectId?: string | null) => ipcRenderer.invoke("sessions:list", projectId) as Promise<Session[]>,
    addManual: (input: SessionInput) => ipcRenderer.invoke("sessions:addManual", input) as Promise<Session>,
    updateManual: (id: string, input: SessionInput) => ipcRenderer.invoke("sessions:updateManual", id, input) as Promise<Session>,
    delete: (id: string) => ipcRenderer.invoke("sessions:delete", id) as Promise<AppSnapshot>
  },
  timer: {
    state: () => ipcRenderer.invoke("timer:state") as Promise<TimerState>,
    start: (projectId: string) => ipcRenderer.invoke("timer:start", projectId) as Promise<TimerState>,
    pause: () => ipcRenderer.invoke("timer:pause") as Promise<TimerState>,
    resume: () => ipcRenderer.invoke("timer:resume") as Promise<TimerState>,
    stop: () => ipcRenderer.invoke("timer:stop") as Promise<TimerState>
  },
  settings: {
    get: () => ipcRenderer.invoke("settings:get") as Promise<AppSettings>,
    update: (input: Partial<AppSettings>) => ipcRenderer.invoke("settings:update", input) as Promise<AppSettings>
  },
  backup: {
    export: () => ipcRenderer.invoke("backup:export") as Promise<BackupPayload | null>,
    import: () => ipcRenderer.invoke("backup:import") as Promise<BackupPayload | null>
  },
  export: {
    table: (table: ExportTable, format: ExportFormat) => ipcRenderer.invoke("export:table", table, format) as Promise<boolean>
  }
};

contextBridge.exposeInMainWorld("worklog", api);

declare global {
  interface Window {
    worklog: typeof api;
  }
}
