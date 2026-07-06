import type { SqlDatabase } from "../data/database";
import type { Project, ProjectInput } from "../../src/shared/types";
import { ensureNoDuplicateProject, validateProjectFields } from "../../src/shared/validation";
import { mapProject } from "../data/mappers";

export class ProjectRepository {
  constructor(private readonly db: SqlDatabase) {}

  fetchAll(includeArchived = false): Project[] {
    const sql = includeArchived
      ? "SELECT * FROM projects ORDER BY name COLLATE NOCASE"
      : "SELECT * FROM projects WHERE is_archived = 0 ORDER BY name COLLATE NOCASE";
    return this.db.prepare(sql).all().map((row) => mapProject(row as never));
  }

  fetchById(id: string): Project | null {
    const row = this.db.prepare("SELECT * FROM projects WHERE id = ?").get(id);
    return row ? mapProject(row as never) : null;
  }

  search(query: string, includeArchived = false): Project[] {
    const term = `%${query.trim()}%`;
    if (!query.trim()) return this.fetchAll(includeArchived);
    const archivedClause = includeArchived ? "" : "AND is_archived = 0";
    return this.db
      .prepare(
        `SELECT * FROM projects
         WHERE (name LIKE ? OR client LIKE ? OR description_text LIKE ?)
         ${archivedClause}
         ORDER BY name COLLATE NOCASE`
      )
      .all(term, term, term)
      .map((row) => mapProject(row as never));
  }

  duplicateMatches(name: string, client: string): Project[] {
    return this.db
      .prepare("SELECT * FROM projects WHERE lower(name) = lower(?) AND lower(client) = lower(?)")
      .all(name.trim(), client.trim())
      .map((row) => mapProject(row as never));
  }

  insert(input: ProjectInput): Project {
    validateProjectFields(input);
    ensureNoDuplicateProject(this.duplicateMatches(input.name, input.client));
    const now = new Date().toISOString();
    const id = crypto.randomUUID();
    this.db
      .prepare(
        `INSERT INTO projects (
          id, name, client, daily_rate, category, tags, description_text,
          status, is_archived, is_favorite, created_at, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
      )
      .run(
        id,
        input.name.trim(),
        input.client.trim(),
        input.dailyRate,
        input.category,
        JSON.stringify(input.tags),
        input.descriptionText.trim(),
        input.status,
        input.isArchived ? 1 : 0,
        input.isFavorite ? 1 : 0,
        now,
        now
      );
    return this.fetchById(id)!;
  }

  upsertRestored(project: Project): Project {
    const now = new Date().toISOString();
    this.db
      .prepare(
        `INSERT INTO projects (
          id, name, client, daily_rate, category, tags, description_text,
          status, is_archived, is_favorite, created_at, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
          name = excluded.name,
          client = excluded.client,
          daily_rate = excluded.daily_rate,
          category = excluded.category,
          tags = excluded.tags,
          description_text = excluded.description_text,
          status = excluded.status,
          is_archived = excluded.is_archived,
          is_favorite = excluded.is_favorite,
          updated_at = excluded.updated_at`
      )
      .run(
        project.id,
        project.name.trim(),
        project.client.trim(),
        project.dailyRate,
        project.category,
        JSON.stringify(project.tags),
        project.descriptionText.trim(),
        project.status,
        project.isArchived ? 1 : 0,
        project.isFavorite ? 1 : 0,
        project.createdAt || now,
        project.updatedAt || now
      );
    return this.fetchById(project.id)!;
  }

  update(id: string, input: ProjectInput): Project {
    validateProjectFields(input);
    ensureNoDuplicateProject(this.duplicateMatches(input.name, input.client), id);
    const now = new Date().toISOString();
    this.db
      .prepare(
        `UPDATE projects SET
          name = ?, client = ?, daily_rate = ?, category = ?, tags = ?,
          description_text = ?, status = ?, is_archived = ?, is_favorite = ?, updated_at = ?
         WHERE id = ?`
      )
      .run(
        input.name.trim(),
        input.client.trim(),
        input.dailyRate,
        input.category,
        JSON.stringify(input.tags),
        input.descriptionText.trim(),
        input.status,
        input.isArchived ? 1 : 0,
        input.isFavorite ? 1 : 0,
        now,
        id
      );
    const project = this.fetchById(id);
    if (!project) throw new Error("Projeto não encontrado.");
    return project;
  }

  archive(id: string, archived: boolean): Project {
    this.db
      .prepare("UPDATE projects SET is_archived = ?, updated_at = ? WHERE id = ?")
      .run(archived ? 1 : 0, new Date().toISOString(), id);
    const project = this.fetchById(id);
    if (!project) throw new Error("Projeto não encontrado.");
    return project;
  }

  delete(id: string): void {
    this.db.prepare("DELETE FROM projects WHERE id = ?").run(id);
  }
}
