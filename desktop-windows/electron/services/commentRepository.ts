import crypto from "node:crypto";
import type { DatabaseSync } from "node:sqlite";
import type { Comment } from "../../src/shared/types";

interface CommentRow {
  id: string;
  project_id: string | null;
  text: string;
  author: string;
  created_at: string;
}

function mapComment(row: CommentRow): Comment {
  return {
    id: row.id,
    projectId: row.project_id,
    text: row.text,
    author: row.author,
    createdAt: row.created_at
  };
}

export class CommentRepository {
  constructor(private readonly db: DatabaseSync) {}

  fetchAll(projectId?: string): Comment[] {
    const rows = projectId
      ? (this.db
          .prepare("SELECT * FROM comments WHERE project_id = ? ORDER BY created_at DESC")
          .all(projectId) as unknown as CommentRow[])
      : (this.db
          .prepare("SELECT * FROM comments ORDER BY created_at DESC")
          .all() as unknown as CommentRow[]);
    return rows.map(mapComment);
  }

  insert(input: { id?: string; projectId: string | null; text: string; author: string; createdAt?: string }): Comment {
    const comment: Comment = {
      id: input.id ?? crypto.randomUUID().toUpperCase(),
      projectId: input.projectId,
      text: input.text,
      author: input.author,
      createdAt: input.createdAt ?? new Date().toISOString()
    };

    this.db
      .prepare(
        "INSERT INTO comments (id, project_id, text, author, created_at) VALUES (?, ?, ?, ?, ?)"
      )
      .run(comment.id, comment.projectId, comment.text, comment.author, comment.createdAt);

    return comment;
  }

  upsertRaw(comment: Comment): void {
    this.db
      .prepare(
        `INSERT INTO comments (id, project_id, text, author, created_at) VALUES (?, ?, ?, ?, ?)
         ON CONFLICT(id) DO UPDATE SET
           project_id = excluded.project_id,
           text = excluded.text,
           author = excluded.author,
           created_at = excluded.created_at`
      )
      .run(comment.id, comment.projectId, comment.text, comment.author, comment.createdAt);
  }

  delete(id: string): void {
    this.db.prepare("DELETE FROM comments WHERE id = ?").run(id);
  }

  deleteAll(): void {
    this.db.prepare("DELETE FROM comments").run();
  }
}
