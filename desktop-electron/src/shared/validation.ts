import type { Project, ProjectInput, SessionInput } from "./types";

export class ValidationError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "ValidationError";
  }
}

export function validateProjectFields(input: Pick<ProjectInput, "name" | "client" | "dailyRate">): void {
  if (!input.name.trim()) throw new ValidationError("O nome do projeto não pode estar vazio.");
  if (!input.client.trim()) throw new ValidationError("O cliente não pode estar vazio.");
  if (input.dailyRate < 0) throw new ValidationError("O valor por dia não pode ser negativo.");
}

export function validateSessionFields(project: Project | null | undefined, input: SessionInput): void {
  if (!project) throw new ValidationError("Selecione um projeto para a sessão.");
  if (new Date(input.endTime) <= new Date(input.startTime)) {
    throw new ValidationError("A hora final deve ser posterior à hora inicial.");
  }
}

export function ensureNoDuplicateProject(matches: Project[], excludingId?: string): void {
  const duplicate = matches.some((project) => project.id !== excludingId);
  if (duplicate) throw new ValidationError("Já existe um projeto com esse nome para esse cliente.");
}
