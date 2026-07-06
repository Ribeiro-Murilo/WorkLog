export type ProjectCategory = "work" | "personal";
export type ProjectStatus = "active" | "inProgress" | "blocked" | "ready";
export type SessionStatus = "running" | "paused" | "completed";
export type AppTheme = "system" | "light" | "dark";
export type TimeFormatPreference = "twelveHour" | "twentyFourHour";

export interface Project {
  id: string;
  name: string;
  client: string;
  dailyRate: number;
  category: ProjectCategory;
  tags: string[];
  descriptionText: string;
  status: ProjectStatus;
  isArchived: boolean;
  isFavorite: boolean;
  createdAt: string;
  updatedAt: string;
}

export interface Session {
  id: string;
  projectId: string | null;
  projectName?: string;
  projectClient?: string;
  date: string;
  startTime: string;
  endTime: string | null;
  durationSeconds: number;
  note: string;
  category: ProjectCategory;
  status: SessionStatus;
  createdAt: string;
  updatedAt: string;
}

export interface AppSettings {
  id: string;
  launchAtLogin: boolean;
  idleTimeoutMinutes: number;
  showSeconds: boolean;
  theme: AppTheme;
  timeFormat: TimeFormatPreference;
  lastBackupDate: string | null;
  createdAt: string;
  updatedAt: string;
}

export interface ProjectInput {
  name: string;
  client: string;
  dailyRate: number;
  category: ProjectCategory;
  tags: string[];
  descriptionText: string;
  status: ProjectStatus;
  isArchived?: boolean;
  isFavorite?: boolean;
}

export interface SessionInput {
  projectId: string;
  startTime: string;
  endTime: string;
  note: string;
}

export interface TimerState {
  activeSession: Session | null;
  activeProject: Project | null;
  elapsedSeconds: number;
  isRunning: boolean;
}

export interface DashboardSummary {
  todaySeconds: number;
  weekSeconds: number;
  monthSeconds: number;
  totalSeconds: number;
  activeProjects: number;
  archivedProjects: number;
  totalValue: number;
  byProject: SummaryBucket[];
  byClient: SummaryBucket[];
  byCategory: SummaryBucket[];
  recentSessions: Session[];
}

export interface SummaryBucket {
  label: string;
  seconds: number;
  value: number;
}

export interface BackupPayload {
  exportedAt: string;
  projects: Project[];
  sessions: Session[];
}

export interface ExportTable {
  title: string;
  headers: string[];
  rows: string[][];
}

export type ExportFormat = "csv" | "excel";
