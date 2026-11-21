export const STANDARD_WORKDAY_HOURS = 8;

import type { CurrencyCode, PtaxState } from "./currency";

export type ProjectCategory = "work" | "personal";
export type ProjectStatus = "active" | "inProgress" | "blocked" | "ready";
export type SessionStatus = "running" | "paused" | "completed";
export type InvoiceStatus = "pending" | "paid";
export type AppTheme = "system" | "light" | "dark";
export type TimeFormatPreference = "twelveHour" | "twentyFourHour";
export type AppDisplayMode = "notch" | "menuBar";
export type ShortcutAction =
  | "startTimer"
  | "pauseTimer"
  | "openDashboard"
  | "openPopover"
  | "searchProject"
  | "newProject";
export type ReportPeriod = "today" | "yesterday" | "week" | "month" | "year" | "custom";
export type ReportGrouping = "detailed" | "byProjectAndDay";
export type ReportColumn =
  | "project"
  | "client"
  | "date"
  | "startTime"
  | "endTime"
  | "duration"
  | "sessionCount"
  | "category"
  | "status"
  | "value"
  | "note"
  | "tags"
  | "description";
export type ExportFormat = "csv" | "excel" | "pdf";
export type ProjectSortOption = "name" | "client" | "createdAt";

export const PROJECT_CATEGORY_LABELS: Record<ProjectCategory, string> = {
  work: "Trabalho",
  personal: "Pessoal"
};

export const PROJECT_STATUS_LABELS: Record<ProjectStatus, string> = {
  active: "Ativo",
  inProgress: "Em execução",
  blocked: "Impedimento",
  ready: "Pronto"
};

export const SESSION_STATUS_LABELS: Record<SessionStatus, string> = {
  running: "Em andamento",
  paused: "Pausada",
  completed: "Concluída"
};

export const INVOICE_STATUS_LABELS: Record<InvoiceStatus, string> = {
  pending: "Pendente",
  paid: "Paga"
};

export const APP_THEME_LABELS: Record<AppTheme, string> = {
  system: "Sistema",
  light: "Claro",
  dark: "Escuro"
};

export const TIME_FORMAT_LABELS: Record<TimeFormatPreference, string> = {
  twelveHour: "12 horas",
  twentyFourHour: "24 horas"
};

export const APP_DISPLAY_MODE_LABELS: Record<AppDisplayMode, string> = {
  notch: "Barra superior (Notch)",
  menuBar: "Bandeja do sistema (Tray)"
};

export const SHORTCUT_ACTION_LABELS: Record<ShortcutAction, string> = {
  startTimer: "Iniciar timer",
  pauseTimer: "Pausar timer",
  openDashboard: "Abrir Dashboard",
  openPopover: "Abrir Painel rápido",
  searchProject: "Pesquisar projeto",
  newProject: "Novo projeto"
};

export const SHORTCUT_ACTIONS: ShortcutAction[] = [
  "startTimer",
  "pauseTimer",
  "openDashboard",
  "openPopover",
  "searchProject",
  "newProject"
];

export const REPORT_PERIOD_LABELS: Record<ReportPeriod, string> = {
  today: "Hoje",
  yesterday: "Ontem",
  week: "Semana",
  month: "Mês",
  year: "Ano",
  custom: "Período personalizado"
};

export const REPORT_GROUPING_LABELS: Record<ReportGrouping, string> = {
  detailed: "Detalhado",
  byProjectAndDay: "Resumido por projeto e dia"
};

export const EXPORT_FORMAT_LABELS: Record<ExportFormat, string> = {
  csv: "CSV",
  excel: "Excel",
  pdf: "PDF"
};

export const PROJECT_SORT_LABELS: Record<ProjectSortOption, string> = {
  name: "Nome",
  client: "Cliente",
  createdAt: "Data de criação"
};

export interface Project {
  id: string;
  name: string;
  client: string;
  dailyRate: number;
  currencyCode: CurrencyCode;
  category: ProjectCategory;
  tags: string[];
  descriptionText: string;
  status: ProjectStatus;
  isArchived: boolean;
  isFavorite: boolean;
  createdAt: string;
  updatedAt: string;
}

export interface ProjectWithStats extends Project {
  totalWorkedSeconds: number;
  totalValue: number;
  sessionCount: number;
}

export interface SessionWorkPeriod {
  start: string;
  end: string | null;
}

export interface Session {
  id: string;
  projectId: string | null;
  date: string;
  startTime: string;
  endTime: string | null;
  durationSeconds: number;
  workPeriods: SessionWorkPeriod[] | null;
  note: string;
  category: ProjectCategory;
  status: SessionStatus;
  createdAt: string;
  updatedAt: string;
}

export interface SessionWithProject extends Session {
  projectName: string;
  projectClient: string;
  normalizedPeriods: SessionWorkPeriod[];
}

export interface Comment {
  id: string;
  projectId: string | null;
  text: string;
  author: string;
  createdAt: string;
}

export interface ReportPreset {
  id: string;
  name: string;
  columns: ReportColumn[];
  grouping: ReportGrouping;
  createdAt: string;
  updatedAt: string;
}

export interface InvoiceLineItem {
  date: string;
  projectName: string;
  durationSeconds: number;
  value: number;
}

export interface Invoice {
  id: string;
  number: number;
  formattedNumber: string;
  client: string;
  issueDate: string;
  periodStart: string;
  periodEnd: string;
  lineItems: InvoiceLineItem[];
  totalDurationSeconds: number;
  totalValue: number;
  currencyCode: CurrencyCode;
  status: InvoiceStatus;
  notes: string;
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
  displayMode: AppDisplayMode;
  notchDisplayId: string | null;
  lastBackupDate: string | null;
  invoiceIssuerName: string;
  invoiceIssuerDetails: string;
  lastInvoiceNumber: number;
  includeLogoInPDF: boolean;
  createdAt: string;
  updatedAt: string;
}

export interface ShortcutBinding {
  action: ShortcutAction;
  accelerator: string;
  isEnabled: boolean;
  updatedAt: string;
}

export interface TimerState {
  activeSession: Session | null;
  activeProject: Project | null;
  resumableSession: Session | null;
  resumableProject: Project | null;
  elapsedSeconds: number;
  isRunning: boolean;
  todayTotalSeconds: number;
}

export interface DisplayInfo {
  id: string;
  label: string;
  isPrimary: boolean;
  bounds: { x: number; y: number; width: number; height: number };
}

export interface NotchUIState {
  isExpanded: boolean;
  isPinned: boolean;
  isRunning: boolean;
  compactElapsed: string | null;
  activeProjectColor: string | null;
}

export interface DashboardSummary {
  todayTotal: number;
  weekTotal: number;
  monthTotal: number;
  allTimeTotal: number;
  activeProjectsCount: number;
  archivedProjectsCount: number;
  recentSessions: SessionWithProject[];
  mostUsedProjects: Array<{ project: Project; total: number }>;
  timeByCategory: Array<{ category: ProjectCategory; total: number }>;
  timeByClient: Array<{ client: string; total: number }>;
  timeByProject: Array<{ project: Project; total: number }>;
}

export interface ReportFilter {
  period: ReportPeriod;
  customStart: string;
  customEnd: string;
  projectId: string | null;
  client: string | null;
  category: ProjectCategory | null;
  status: SessionStatus | null;
  tag: string | null;
  selectedColumns: ReportColumn[];
  grouping: ReportGrouping;
}

export interface ReportRow {
  id: string;
  projectName: string;
  client: string;
  date: string;
  startTime: string;
  endTime: string | null;
  durationSeconds: number;
  category: ProjectCategory;
  status: SessionStatus;
  estimatedValue: number;
  currencyCode: CurrencyCode;
  note: string;
  tags: string[];
  descriptionText: string;
  sessionCount: number;
}

export interface ReportResult {
  rows: ReportRow[];
  totalDuration: number;
  totalsByCurrency: Partial<Record<CurrencyCode, number>>;
  columns: ReportColumn[];
  periodLabel: string;
}

export interface BillingPreview {
  client: string | null;
  periodStart: string;
  periodEnd: string;
  lineItems: InvoiceLineItem[];
  totalDurationSeconds: number;
  totalValue: number;
  currencyCode: CurrencyCode;
  overlapsExistingInvoice: boolean;
}

export interface ConflictInfo {
  sessionId: string;
  projectName: string;
  intervals: Array<{ start: string; end: string | null }>;
}

export interface AvailabilityCheck {
  conflicts: ConflictInfo[];
  suggestedInterval: { start: string; end: string } | null;
  cycleProblem: string | null;
}

export interface ProjectInput {
  name: string;
  client: string;
  dailyRate: number;
  currencyCode?: CurrencyCode;
  category: ProjectCategory;
  tags: string[];
  descriptionText: string;
  status: ProjectStatus;
}

export interface SessionUpdateInput {
  startTime: string;
  endTime: string;
  note: string;
  workPeriods?: SessionWorkPeriod[];
  expectedUpdatedAt?: string;
  expectedWorkPeriods?: SessionWorkPeriod[];
  expectedStatus?: SessionStatus;
}

export interface AppSnapshot {
  projects: ProjectWithStats[];
  sessions: SessionWithProject[];
  recentSessions: SessionWithProject[];
  commentsByProject: Record<string, Comment[]>;
  presets: ReportPreset[];
  invoices: Invoice[];
  settings: AppSettings;
  shortcuts: ShortcutBinding[];
  timer: TimerState;
  dashboard: DashboardSummary;
  displays: DisplayInfo[];
  notch: NotchUIState;
  appVersion: string;
  ptax: PtaxState;
}

export type DashboardSection = "summary" | "projects" | "reports" | "billing" | "settings";
