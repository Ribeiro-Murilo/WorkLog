import crypto from "node:crypto";
import type { DatabaseSync } from "node:sqlite";
import type { Project, ProjectCategory, ProjectInput, ProjectStatus } from "../../src/shared/types";
import { VALIDATION_MESSAGES, ValidationError, validateProjectFields } from "../../src/shared/validation";

interface ProjectRow {
  id: string;
  name: string;
  client: string;
  daily_rate: number;
  category: string;
  tags_json: string;
  description_text: string;
  status: string;
  is_archived: number;
  is_favorite: number;
  created_at: string;
  updated_at: string;
}

function mapProject(row: ProjectRow): Project {
  let tags: string[] = [];
  try {
    const parsed = JSON.parse(row.tags_json);
    if (Array.isArray(parsed)) tags = parsed.map((v) => String(v));
  } catch {
    tags = [];
  }
  return {
    id: row.id,
    name: row.name,
    client: row.client,
    dailyRate: Number(row.daily_rate) || 0,
    category: (row.category === "personal" ? "personal" : "work") as ProjectCategory,
    tags,
    descriptionText: row.description_text,
    status: (["active", "inProgress", "blocked", "ready"].includes(row.status)
      ? row.status
      : "active") as ProjectStatus,
    isArchived: row.is_archived === 1,
    isFavorite: row.is_favorite === 1,
    createdAt: row.created_at,
    updatedAt: row.updated_at
  };
}

export class ProjectRepository {
  constructor(private readonly db: DatabaseSync) {}

  fetchAll(includeArchived: boolean): Project[] {
    const sql = includeArchived
      ? "SELECT * FROM projects ORDER BY name COLLATE NOCASE ASC"
      : "SELECT * FROM projects WHERE is_archived = 0 ORDER BY name COLLATE NOCASE ASC";
    const rows = this.db.prepare(sql).all() as unknown as ProjectRow[];
    return rows.map(mapProject);
  }

  fetchById(id: string): Project | null {
    const row = this.db.prepare("SELECT * FROM projects WHERE id = ?").get(id) as
      | ProjectRow
      | undefined;
    return row ? mapProject(row) : null;
  }

  search(query: string, includeArchived: boolean): Project[] {
    const all = this.fetchAll(includeArchived);
    const trimmed = query.trim().toLocaleLowerCase("pt-BR");
    if (!trimmed) return all;
    return all.filter(
      (p) =>
        p.name.toLocaleLowerCase("pt-BR").includes(trimmed) ||
        p.client.toLocaleLowerCase("pt-BR").includes(trimmed) ||
        p.descriptionText.toLocaleLowerCase("pt-BR").includes(trimmed)
    );
  }

  isDuplicate(name: string, client: string, excludingId?: string): boolean {
    const rows = this.db
      .prepare("SELECT id FROM projects WHERE name = ? AND client = ?")
      .all(name, client) as Array<{ id: string }>;
    if (excludingId) {
      return rows.some((row) => row.id !== excludingId);
    }
    return rows.length > 0;
  }

  insert(input: ProjectInput, explicit?: { id?: string; createdAt?: string; updatedAt?: string; isArchived?: boolean; isFavorite?: boolean }): Project {
    validateProjectFields(input.name, input.client, input.dailyRate);
    const trimmedName = input.name.trim();
    const trimmedClient = input.client.trim();
    if (!explicit?.id && this.isDuplicate(trimmedName, trimmedClient)) {
      throw new ValidationError(VALIDATION_MESSAGES.duplicateProject);
    }

    const now = new Date().toISOString();
    const project: Project = {
      id: explicit?.id ?? crypto.randomUUID().toUpperCase(),
      name: input.name,
      client: input.client,
      dailyRate: input.dailyRate,
      category: input.category,
      tags: input.tags,
      descriptionText: input.descriptionText,
      status: input.status,
      isArchived: explicit?.isArchived ?? false,
      isFavorite: explicit?.isFavorite ?? false,
      createdAt: explicit?.createdAt ?? now,
      updatedAt: explicit?.updatedAt ?? now
    };

    this.db
      .prepare(
        `INSERT INTO projects (
          id, name, client, daily_rate, category, tags_json, description_text,
          status, is_archived, is_favorite, created_at, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
      )
      .run(
        project.id,
        project.name,
        project.client,
        project.dailyRate,
        project.category,
        JSON.stringify(project.tags),
        project.descriptionText,
        project.status,
        project.isArchived ? 1 : 0,
        project.isFavorite ? 1 : 0,
        project.createdAt,
        project.updatedAt
      );

    return project;
  }

  update(id: string, input: ProjectInput): Project {
    const existing = this.fetchById(id);
    if (!existing) throw new Error("Projeto não encontrado.");
    validateProjectFields(input.name, input.client, input.dailyRate);
    const trimmedName = input.name.trim();
    const trimmedClient = input.client.trim();
    if (this.isDuplicate(trimmedName, trimmedClient, id)) {
      throw new ValidationError(VALIDATION_MESSAGES.duplicateProject);
    }

    const updatedAt = new Date().toISOString();
    this.db
      .prepare(
        `UPDATE projects SET
          name = ?, client = ?, daily_rate = ?, category = ?, tags_json = ?,
          description_text = ?, status = ?, updated_at = ?
        WHERE id = ?`
      )
      .run(
        input.name,
        input.client,
        input.dailyRate,
        input.category,
        JSON.stringify(input.tags),
        input.descriptionText,
        input.status,
        updatedAt,
        id
      );

    return this.fetchById(id)!;
  }

  upsertRaw(project: Project): void {
    this.db
      .prepare(
        `INSERT INTO projects (
          id, name, client, daily_rate, category, tags_json, description_text,
          status, is_archived, is_favorite, created_at, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
          name = excluded.name,
          client = excluded.client,
          daily_rate = excluded.daily_rate,
          category = excluded.category,
          tags_json = excluded.tags_json,
          description_text = excluded.description_text,
          status = excluded.status,
          is_archived = excluded.is_archived,
          is_favorite = excluded.is_favorite,
          created_at = excluded.created_at,
          updated_at = excluded.updated_at`
      )
      .run(
        project.id,
        project.name,
        project.client,
        project.dailyRate,
        project.category,
        JSON.stringify(project.tags),
        project.descriptionText,
        project.status,
        project.isArchived ? 1 : 0,
        project.isFavorite ? 1 : 0,
        project.createdAt,
        project.updatedAt
      );
  }

  archive(id: string, archived: boolean): Project {
    const existing = this.fetchById(id);
    if (!existing) throw new Error("Projeto não encontrado.");
    const updatedAt = new Date().toISOString();
    this.db
      .prepare("UPDATE projects SET is_archived = ?, updated_at = ? WHERE id = ?")
      .run(archived ? 1 : 0, updatedAt, id);
    return this.fetchById(id)!;
  }

  toggleFavorite(id: string): Project {
    const existing = this.fetchById(id);
    if (!existing) throw new Error("Projeto não encontrado.");
    const updatedAt = new Date().toISOString();
    this.db
      .prepare("UPDATE projects SET is_favorite = ?, updated_at = ? WHERE id = ?")
      .run(existing.isFavorite ? 0 : 1, updatedAt, id);
    return this.fetchById(id)!;
  }

  delete(id: string): void {
    this.db.prepare("DELETE FROM projects WHERE id = ?").run(id);
  }

  deleteAll(): void {
    this.db.prepare("DELETE FROM projects").run();
  }
}
