import { contextBridge, ipcRenderer } from "electron";
import type {
  AppSettings,
  AppSnapshot,
  AvailabilityCheck,
  BillingPreview,
  DashboardSection,
  ExportFormat,
  ProjectInput,
  ReportFilter,
  ReportGrouping,
  ReportPeriod,
  ReportResult,
  ReportColumn,
  SessionUpdateInput,
  SessionWorkPeriod,
  ShortcutAction
} from "../src/shared/types";

export interface WorkLogBridge {
  getSnapshot: () => Promise<AppSnapshot>;
  onSnapshot: (listener: (snapshot: AppSnapshot) => void) => () => void;
  onNavigate: (listener: (section: DashboardSection, focusSearch?: boolean, openNewProject?: boolean) => void) => () => void;

  timer: {
    start: (projectId: string) => Promise<void>;
    pause: () => Promise<void>;
    resume: (projectId?: string | null) => Promise<void>;
    stop: () => Promise<void>;
  };

  projects: {
    create: (input: ProjectInput) => Promise<void>;
    update: (id: string, input: ProjectInput) => Promise<void>;
    delete: (id: string) => Promise<void>;
    archive: (id: string, archived: boolean) => Promise<void>;
    toggleFavorite: (id: string) => Promise<void>;
  };

  comments: {
    add: (projectId: string, text: string) => Promise<void>;
    delete: (id: string) => Promise<void>;
  };

  sessions: {
    addManual: (input: { projectId: string; startTime: string; endTime: string; note: string }) => Promise<void>;
    update: (sessionId: string, input: SessionUpdateInput) => Promise<void>;
    delete: (sessionId: string) => Promise<void>;
    checkAvailability: (params: {
      startTime: string;
      endTime: string;
      excludingSessionId?: string | null;
      workPeriods?: SessionWorkPeriod[];
    }) => Promise<AvailabilityCheck>;
  };

  reports: {
    generate: (filter: ReportFilter) => Promise<ReportResult>;
    export: (filter: ReportFilter, format: ExportFormat) => Promise<{ saved: boolean; filePath?: string }>;
    savePreset: (name: string, columns: ReportColumn[], grouping: ReportGrouping) => Promise<void>;
    deletePreset: (id: string) => Promise<void>;
  };

  billing: {
    availableClients: () => Promise<string[]>;
    preview: (params: {
      client: string | null;
      period: ReportPeriod;
      customStart: string;
      customEnd: string;
    }) => Promise<BillingPreview>;
    generateInvoice: (params: {
      client: string;
      period: ReportPeriod;
      customStart: string;
      customEnd: string;
      notes: string;
    }) => Promise<void>;
    toggleStatus: (invoiceId: string) => Promise<void>;
    deleteInvoice: (invoiceId: string) => Promise<void>;
    exportPdf: (invoiceId: string) => Promise<{ saved: boolean; filePath?: string }>;
  };

  settings: {
    save: (patch: Partial<AppSettings>) => Promise<void>;
    updateShortcut: (action: ShortcutAction, accelerator: string) => Promise<void>;
  };

  backup: {
    exportJson: () => Promise<{ saved: boolean; filePath?: string }>;
    importJson: () => Promise<{ imported: boolean; error?: string }>;
  };

  notch: {
    setPinned: (pinned: boolean) => Promise<void>;
    setExpandedHeight: (height: number) => Promise<void>;
    setEditing: (editing: boolean) => Promise<void>;
    setMenuOpen: (open: boolean) => Promise<void>;
    expand: () => Promise<void>;
    collapse: () => Promise<void>;
  };

  app: {
    openDashboard: (section?: DashboardSection) => Promise<void>;
    quit: () => Promise<void>;
  };
}

const api: WorkLogBridge = {
  getSnapshot: () => ipcRenderer.invoke("app:getSnapshot"),
  onSnapshot: (listener) => {
    const handler = (_event: Electron.IpcRendererEvent, snapshot: AppSnapshot) => {
      listener(snapshot);
    };
    ipcRenderer.on("app:snapshot", handler);
    return () => ipcRenderer.removeListener("app:snapshot", handler);
  },
  onNavigate: (listener) => {
    const handler = (
      _event: Electron.IpcRendererEvent,
      payload: { section: DashboardSection; focusSearch?: boolean; openNewProject?: boolean }
    ) => {
      listener(payload.section, payload.focusSearch, payload.openNewProject);
    };
    ipcRenderer.on("app:navigate", handler);
    return () => ipcRenderer.removeListener("app:navigate", handler);
  },

  timer: {
    start: (projectId) => ipcRenderer.invoke("timer:start", projectId),
    pause: () => ipcRenderer.invoke("timer:pause"),
    resume: (projectId) => ipcRenderer.invoke("timer:resume", projectId),
    stop: () => ipcRenderer.invoke("timer:stop")
  },

  projects: {
    create: (input) => ipcRenderer.invoke("projects:create", input),
    update: (id, input) => ipcRenderer.invoke("projects:update", id, input),
    delete: (id) => ipcRenderer.invoke("projects:delete", id),
    archive: (id, archived) => ipcRenderer.invoke("projects:archive", id, archived),
    toggleFavorite: (id) => ipcRenderer.invoke("projects:toggleFavorite", id)
  },

  comments: {
    add: (projectId, text) => ipcRenderer.invoke("comments:add", projectId, text),
    delete: (id) => ipcRenderer.invoke("comments:delete", id)
  },

  sessions: {
    addManual: (input) => ipcRenderer.invoke("sessions:addManual", input),
    update: (sessionId, input) => ipcRenderer.invoke("sessions:update", sessionId, input),
    delete: (sessionId) => ipcRenderer.invoke("sessions:delete", sessionId),
    checkAvailability: (params) => ipcRenderer.invoke("sessions:checkAvailability", params)
  },

  reports: {
    generate: (filter) => ipcRenderer.invoke("reports:generate", filter),
    export: (filter, format) => ipcRenderer.invoke("reports:export", filter, format),
    savePreset: (name, columns, grouping) =>
      ipcRenderer.invoke("reports:savePreset", name, columns, grouping),
    deletePreset: (id) => ipcRenderer.invoke("reports:deletePreset", id)
  },

  billing: {
    availableClients: () => ipcRenderer.invoke("billing:availableClients"),
    preview: (params) => ipcRenderer.invoke("billing:preview", params),
    generateInvoice: (params) => ipcRenderer.invoke("billing:generateInvoice", params),
    toggleStatus: (invoiceId) => ipcRenderer.invoke("billing:toggleStatus", invoiceId),
    deleteInvoice: (invoiceId) => ipcRenderer.invoke("billing:deleteInvoice", invoiceId),
    exportPdf: (invoiceId) => ipcRenderer.invoke("billing:exportPdf", invoiceId)
  },

  settings: {
    save: (patch) => ipcRenderer.invoke("settings:save", patch),
    updateShortcut: (action, accelerator) =>
      ipcRenderer.invoke("settings:updateShortcut", action, accelerator)
  },

  backup: {
    exportJson: () => ipcRenderer.invoke("backup:exportJson"),
    importJson: () => ipcRenderer.invoke("backup:importJson")
  },

  notch: {
    setPinned: (pinned) => ipcRenderer.invoke("notch:setPinned", pinned),
    setExpandedHeight: (height) => ipcRenderer.invoke("notch:setExpandedHeight", height),
    setEditing: (editing) => ipcRenderer.invoke("notch:setEditing", editing),
    setMenuOpen: (open) => ipcRenderer.invoke("notch:setMenuOpen", open),
    expand: () => ipcRenderer.invoke("notch:expand"),
    collapse: () => ipcRenderer.invoke("notch:collapse")
  },

  app: {
    openDashboard: (section) => ipcRenderer.invoke("app:openDashboard", section),
    quit: () => ipcRenderer.invoke("app:quit")
  }
};

contextBridge.exposeInMainWorld("worklog", api);
