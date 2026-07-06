/// <reference types="vite/client" />

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
} from "./shared/types";

export interface AppSnapshot {
  projects: Project[];
  sessions: Session[];
  settings: AppSettings;
  timer: TimerState;
  dashboard: DashboardSummary;
}

declare global {
  interface Window {
    worklog: {
      snapshot: () => Promise<AppSnapshot>;
      onSnapshotChanged: (callback: (snapshot: AppSnapshot) => void) => () => void;
      projects: {
        list: (includeArchived?: boolean) => Promise<Project[]>;
        save: (id: string | null, input: ProjectInput) => Promise<Project>;
        archive: (id: string, archived: boolean) => Promise<Project>;
        delete: (id: string) => Promise<AppSnapshot>;
      };
      sessions: {
        list: (projectId?: string | null) => Promise<Session[]>;
        addManual: (input: SessionInput) => Promise<Session>;
        updateManual: (id: string, input: SessionInput) => Promise<Session>;
        delete: (id: string) => Promise<AppSnapshot>;
      };
      timer: {
        state: () => Promise<TimerState>;
        start: (projectId: string) => Promise<TimerState>;
        pause: () => Promise<TimerState>;
        resume: () => Promise<TimerState>;
        stop: () => Promise<TimerState>;
      };
      settings: {
        get: () => Promise<AppSettings>;
        update: (input: Partial<AppSettings>) => Promise<AppSettings>;
      };
      backup: {
        export: () => Promise<BackupPayload | null>;
        import: () => Promise<BackupPayload | null>;
      };
      export: {
        table: (table: ExportTable, format: ExportFormat) => Promise<boolean>;
      };
    };
  }
}
