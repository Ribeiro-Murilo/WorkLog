import crypto from "node:crypto";
import type { DatabaseSync } from "node:sqlite";
import {
  getLatestActivityMs,
  getOccupiedWorkIntervals,
  intervalsOverlap
} from "../../src/shared/periods";
import type {
  ProjectCategory,
  Session,
  SessionStatus,
  SessionWorkPeriod
} from "../../src/shared/types";

interface SessionRow {
  id: string;
  project_id: string | null;
  date: string;
  start_time: string;
  end_time: string | null;
  duration_seconds: number;
  work_periods_json: string | null;
  note: string;
  category: string;
  status: string;
  created_at: string;
  updated_at: string;
}

function mapSession(row: SessionRow): Session {
  let workPeriods: SessionWorkPeriod[] | null = null;
  if (row.work_periods_json) {
    try {
      const parsed = JSON.parse(row.work_periods_json);
      if (Array.isArray(parsed)) {
        workPeriods = parsed.map((p) => ({
          start: String(p.start),
          end: p.end ? String(p.end) : null
        }));
      }
    } catch {
      workPeriods = null;
    }
  }

  return {
    id: row.id,
    projectId: row.project_id,
    date: row.date,
    startTime: row.start_time,
    endTime: row.end_time,
    durationSeconds: Number(row.duration_seconds) || 0,
    workPeriods,
    note: row.note,
    category: (row.category === "personal" ? "personal" : "work") as ProjectCategory,
    status: (["running", "paused", "completed"].includes(row.status)
      ? row.status
      : "completed") as SessionStatus,
    createdAt: row.created_at,
    updatedAt: row.updated_at
  };
}

export class SessionRepository {
  constructor(private readonly db: DatabaseSync) {}

  fetchAll(projectId?: string | null): Session[] {
    const rows = projectId
      ? (this.db
          .prepare("SELECT * FROM sessions WHERE project_id = ? ORDER BY start_time DESC")
          .all(projectId) as unknown as SessionRow[])
      : (this.db
          .prepare("SELECT * FROM sessions ORDER BY start_time DESC")
          .all() as unknown as SessionRow[]);
    return rows.map(mapSession).sort((a, b) => getLatestActivityMs(b) - getLatestActivityMs(a));
  }

  fetchById(id: string): Session | null {
    const row = this.db.prepare("SELECT * FROM sessions WHERE id = ?").get(id) as
      | SessionRow
      | undefined;
    return row ? mapSession(row) : null;
  }

  fetchActiveSession(): Session | null {
    const row = this.db
      .prepare("SELECT * FROM sessions WHERE status = 'running' ORDER BY start_time DESC LIMIT 1")
      .get() as SessionRow | undefined;
    return row ? mapSession(row) : null;
  }

  fetchSessionsInInterval(startMs: number, endMs: number): Session[] {
    return this.fetchAll(null).filter((session) =>
      getOccupiedWorkIntervals(session).some((interval) =>
        intervalsOverlap(interval.startMs, interval.endMs, startMs, endMs)
      )
    );
  }

  fetchRecent(limit: number): Session[] {
    return this.fetchAll(null).slice(0, Math.max(0, limit));
  }

  conflictingSessions(startMs: number, endMs: number, excludingId?: string | null): Session[] {
    if (!(endMs > startMs)) return [];
    return this.fetchAll(null)
      .filter((session) => {
        if (excludingId && session.id === excludingId) return false;
        return getOccupiedWorkIntervals(session).some((interval) =>
          intervalsOverlap(interval.startMs, interval.endMs, startMs, endMs)
        );
      })
      .sort((a, b) => getLatestActivityMs(a) - getLatestActivityMs(b));
  }

  hasOverlap(startMs: number, endMs: number, excludingId?: string | null): boolean {
    return this.conflictingSessions(startMs, endMs, excludingId).length > 0;
  }

  insert(input: {
    id?: string;
    projectId: string | null;
    date: string;
    startTime: string;
    endTime: string | null;
    durationSeconds: number;
    workPeriods: SessionWorkPeriod[] | null;
    note: string;
    category: ProjectCategory;
    status: SessionStatus;
    createdAt?: string;
    updatedAt?: string;
  }): Session {
    const now = new Date().toISOString();
    const session: Session = {
      id: input.id ?? crypto.randomUUID().toUpperCase(),
      projectId: input.projectId,
      date: input.date,
      startTime: input.startTime,
      endTime: input.endTime,
      durationSeconds: input.durationSeconds,
      workPeriods: input.workPeriods,
      note: input.note,
      category: input.category,
      status: input.status,
      createdAt: input.createdAt ?? now,
      updatedAt: input.updatedAt ?? now
    };

    this.db
      .prepare(
        `INSERT INTO sessions (
          id, project_id, date, start_time, end_time, duration_seconds,
          work_periods_json, note, category, status, created_at, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
      )
      .run(
        session.id,
        session.projectId,
        session.date,
        session.startTime,
        session.endTime,
        session.durationSeconds,
        session.workPeriods ? JSON.stringify(session.workPeriods) : null,
        session.note,
        session.category,
        session.status,
        session.createdAt,
        session.updatedAt
      );

    return session;
  }

  update(session: Session): Session {
    const updatedAt = new Date().toISOString();
    this.db
      .prepare(
        `UPDATE sessions SET
          project_id = ?, date = ?, start_time = ?, end_time = ?, duration_seconds = ?,
          work_periods_json = ?, note = ?, category = ?, status = ?, updated_at = ?
        WHERE id = ?`
      )
      .run(
        session.projectId,
        session.date,
        session.startTime,
        session.endTime,
        session.durationSeconds,
        session.workPeriods ? JSON.stringify(session.workPeriods) : null,
        session.note,
        session.category,
        session.status,
        updatedAt,
        session.id
      );
    return this.fetchById(session.id)!;
  }

  upsertRaw(session: Session): void {
    this.db
      .prepare(
        `INSERT INTO sessions (
          id, project_id, date, start_time, end_time, duration_seconds,
          work_periods_json, note, category, status, created_at, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
          project_id = excluded.project_id,
          date = excluded.date,
          start_time = excluded.start_time,
          end_time = excluded.end_time,
          duration_seconds = excluded.duration_seconds,
          work_periods_json = excluded.work_periods_json,
          note = excluded.note,
          category = excluded.category,
          status = excluded.status,
          created_at = excluded.created_at,
          updated_at = excluded.updated_at`
      )
      .run(
        session.id,
        session.projectId,
        session.date,
        session.startTime,
        session.endTime,
        session.durationSeconds,
        session.workPeriods ? JSON.stringify(session.workPeriods) : null,
        session.note,
        session.category,
        session.status,
        session.createdAt,
        session.updatedAt
      );
  }

  delete(id: string): void {
    this.db.prepare("DELETE FROM sessions WHERE id = ?").run(id);
  }

  deleteAll(): void {
    this.db.prepare("DELETE FROM sessions").run();
  }
}
