import type { AppSettings, Project, Session } from "../../src/shared/types";

interface ProjectRow {
  id: string;
  name: string;
  client: string;
  daily_rate: number;
  category: Project["category"];
  tags: string;
  description_text: string;
  status: Project["status"];
  is_archived: number;
  is_favorite: number;
  created_at: string;
  updated_at: string;
}

interface SessionRow {
  id: string;
  project_id: string | null;
  project_name?: string;
  project_client?: string;
  date: string;
  start_time: string;
  end_time: string | null;
  duration_seconds: number;
  note: string;
  category: Session["category"];
  status: Session["status"];
  created_at: string;
  updated_at: string;
}

interface SettingsRow {
  id: string;
  launch_at_login: number;
  idle_timeout_minutes: number;
  show_seconds: number;
  theme: AppSettings["theme"];
  time_format: AppSettings["timeFormat"];
  last_backup_date: string | null;
  created_at: string;
  updated_at: string;
}

export function mapProject(row: ProjectRow): Project {
  return {
    id: row.id,
    name: row.name,
    client: row.client,
    dailyRate: row.daily_rate,
    category: row.category,
    tags: safeJsonArray(row.tags),
    descriptionText: row.description_text,
    status: row.status,
    isArchived: Boolean(row.is_archived),
    isFavorite: Boolean(row.is_favorite),
    createdAt: row.created_at,
    updatedAt: row.updated_at
  };
}

export function mapSession(row: SessionRow): Session {
  return {
    id: row.id,
    projectId: row.project_id,
    projectName: row.project_name,
    projectClient: row.project_client,
    date: row.date,
    startTime: row.start_time,
    endTime: row.end_time,
    durationSeconds: row.duration_seconds,
    note: row.note,
    category: row.category,
    status: row.status,
    createdAt: row.created_at,
    updatedAt: row.updated_at
  };
}

export function mapSettings(row: SettingsRow): AppSettings {
  return {
    id: row.id,
    launchAtLogin: Boolean(row.launch_at_login),
    idleTimeoutMinutes: row.idle_timeout_minutes,
    showSeconds: Boolean(row.show_seconds),
    theme: row.theme,
    timeFormat: row.time_format,
    lastBackupDate: row.last_backup_date,
    createdAt: row.created_at,
    updatedAt: row.updated_at
  };
}

function safeJsonArray(value: string): string[] {
  try {
    const parsed = JSON.parse(value);
    return Array.isArray(parsed) ? parsed.map(String) : [];
  } catch {
    return [];
  }
}
