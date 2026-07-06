import type { SqlDatabase } from "../data/database";
import type { ProjectCategory, Session, SessionStatus } from "../../src/shared/types";
import { mapSession } from "../data/mappers";

export interface SessionCreateInput {
  projectId: string | null;
  date: string;
  startTime: string;
  endTime: string | null;
  durationSeconds: number;
  note: string;
  category: ProjectCategory;
  status: SessionStatus;
}

export class SessionRepository {
  constructor(private readonly db: SqlDatabase) {}

  fetchAll(projectId?: string | null): Session[] {
    const base = sessionSelect();
    const rows = projectId
      ? this.db.prepare(`${base} WHERE s.project_id = ? ORDER BY s.start_time DESC`).all(projectId)
      : this.db.prepare(`${base} ORDER BY s.start_time DESC`).all();
    return rows.map((row) => mapSession(row as never));
  }

  fetchInRange(start: string, end: string): Session[] {
    return this.db
      .prepare(`${sessionSelect()} WHERE s.start_time >= ? AND s.start_time <= ? ORDER BY s.start_time DESC`)
      .all(start, end)
      .map((row) => mapSession(row as never));
  }

  fetchActive(): Session | null {
    const row = this.db.prepare(`${sessionSelect()} WHERE s.status = 'running' ORDER BY s.start_time DESC LIMIT 1`).get();
    return row ? mapSession(row as never) : null;
  }

  fetchRecent(limit: number): Session[] {
    return this.db
      .prepare(`${sessionSelect()} ORDER BY s.start_time DESC LIMIT ?`)
      .all(limit)
      .map((row) => mapSession(row as never));
  }

  hasOverlap(start: string, end: string, excludingId?: string | null): boolean {
    const rows = this.db
      .prepare(
        `SELECT id FROM sessions
         WHERE start_time < ?
           AND COALESCE(end_time, '9999-12-31T23:59:59.999Z') > ?`
      )
      .all(end, start) as Array<{ id: string }>;
    return rows.some((row) => row.id !== excludingId);
  }

  insert(input: SessionCreateInput): Session {
    const id = crypto.randomUUID();
    const now = new Date().toISOString();
    this.db
      .prepare(
        `INSERT INTO sessions (
          id, project_id, date, start_time, end_time, duration_seconds,
          note, category, status, created_at, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
      )
      .run(
        id,
        input.projectId,
        input.date,
        input.startTime,
        input.endTime,
        input.durationSeconds,
        input.note,
        input.category,
        input.status,
        now,
        now
      );
    return this.fetchById(id)!;
  }

  upsertRestored(session: Session): Session {
    const now = new Date().toISOString();
    this.db
      .prepare(
        `INSERT INTO sessions (
          id, project_id, date, start_time, end_time, duration_seconds,
          note, category, status, created_at, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
          project_id = excluded.project_id,
          date = excluded.date,
          start_time = excluded.start_time,
          end_time = excluded.end_time,
          duration_seconds = excluded.duration_seconds,
          note = excluded.note,
          category = excluded.category,
          status = excluded.status,
          updated_at = excluded.updated_at`
      )
      .run(
        session.id,
        session.projectId,
        session.date,
        session.startTime,
        session.endTime,
        session.durationSeconds,
        session.note,
        session.category,
        session.status,
        session.createdAt || now,
        session.updatedAt || now
      );
    return this.fetchById(session.id)!;
  }

  fetchById(id: string): Session | null {
    const row = this.db.prepare(`${sessionSelect()} WHERE s.id = ?`).get(id);
    return row ? mapSession(row as never) : null;
  }

  update(id: string, patch: Partial<Omit<SessionCreateInput, "projectId">> & { projectId?: string | null }): Session {
    const current = this.fetchById(id);
    if (!current) throw new Error("Sessão não encontrada.");
    const next = {
      projectId: patch.projectId ?? current.projectId,
      date: patch.date ?? current.date,
      startTime: patch.startTime ?? current.startTime,
      endTime: patch.endTime === undefined ? current.endTime : patch.endTime,
      durationSeconds: patch.durationSeconds ?? current.durationSeconds,
      note: patch.note ?? current.note,
      category: patch.category ?? current.category,
      status: patch.status ?? current.status
    };
    this.db
      .prepare(
        `UPDATE sessions SET
          project_id = ?, date = ?, start_time = ?, end_time = ?, duration_seconds = ?,
          note = ?, category = ?, status = ?, updated_at = ?
         WHERE id = ?`
      )
      .run(
        next.projectId,
        next.date,
        next.startTime,
        next.endTime,
        next.durationSeconds,
        next.note,
        next.category,
        next.status,
        new Date().toISOString(),
        id
      );
    return this.fetchById(id)!;
  }

  delete(id: string): void {
    this.db.prepare("DELETE FROM sessions WHERE id = ?").run(id);
  }
}

function sessionSelect(): string {
  return `
    SELECT
      s.*,
      p.name AS project_name,
      p.client AS project_client
    FROM sessions s
    LEFT JOIN projects p ON p.id = s.project_id
  `;
}
