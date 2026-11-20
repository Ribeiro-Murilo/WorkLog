import { formatDateTimeSeconds } from "./format";
import type { SessionWorkPeriod } from "./types";

export const VALIDATION_MESSAGES = {
  emptyName: "O nome do projeto não pode estar vazio.",
  emptyClient: "O cliente não pode estar vazio.",
  negativeRate: "O valor por dia não pode ser negativo.",
  duplicateProject: "Já existe um projeto com esse nome para esse cliente.",
  invalidDateRange: "A hora final deve ser posterior à hora inicial.",
  overlappingSession: "Já existe uma sessão registrada nesse período.",
  missingProject: "Selecione um projeto para a sessão."
} as const;

export class ValidationError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "ValidationError";
  }
}

export function validateProjectFields(name: string, client: string, dailyRate: number): void {
  if (!name.trim()) {
    throw new ValidationError(VALIDATION_MESSAGES.emptyName);
  }
  if (!client.trim()) {
    throw new ValidationError(VALIDATION_MESSAGES.emptyClient);
  }
  if (!Number.isFinite(dailyRate) || dailyRate < 0) {
    throw new ValidationError(VALIDATION_MESSAGES.negativeRate);
  }
}

export function validateSessionFields(
  projectId: string | null | undefined,
  startIso: string,
  endIso: string | null | undefined
): void {
  if (!projectId) {
    throw new ValidationError(VALIDATION_MESSAGES.missingProject);
  }
  const startMs = Date.parse(startIso);
  if (!Number.isFinite(startMs)) {
    throw new ValidationError(VALIDATION_MESSAGES.invalidDateRange);
  }
  if (endIso !== null && endIso !== undefined) {
    const endMs = Date.parse(endIso);
    if (!Number.isFinite(endMs) || endMs <= startMs) {
      throw new ValidationError(VALIDATION_MESSAGES.invalidDateRange);
    }
  }
}

export interface CycleConflictMatch {
  projectName: string;
  intervalStartIso: string;
  intervalEndIso: string | null;
}

export function validateCycles(
  periods: SessionWorkPeriod[],
  findConflict: (startMs: number, endMs: number) => CycleConflictMatch | null
): string | null {
  for (let index = 0; index < periods.length; index++) {
    const period = periods[index];
    if (!period.end) {
      return `Ciclo ${index + 1}: o fim deve ser posterior ao início.`;
    }
    const startMs = Date.parse(period.start);
    const endMs = Date.parse(period.end);
    if (!Number.isFinite(startMs) || !Number.isFinite(endMs) || endMs <= startMs) {
      return `Ciclo ${index + 1}: o fim deve ser posterior ao início.`;
    }
    if (index > 0) {
      const prevEnd = periods[index - 1].end;
      const prevEndMs = prevEnd ? Date.parse(prevEnd) : Number.NaN;
      if (Number.isFinite(prevEndMs) && startMs < prevEndMs) {
        return `Ciclo ${index + 1}: o início deve ser igual ou posterior ao fim do ciclo ${index}.`;
      }
    }
  }

  for (let index = 0; index < periods.length; index++) {
    const period = periods[index];
    if (!period.end) continue;
    const startMs = Date.parse(period.start);
    const endMs = Date.parse(period.end);
    const conflict = findConflict(startMs, endMs);
    if (conflict) {
      const startText = formatDateTimeSeconds(conflict.intervalStartIso);
      const endText = conflict.intervalEndIso
        ? formatDateTimeSeconds(conflict.intervalEndIso)
        : "em andamento";
      return `Ciclo ${index + 1}: conflito com ${conflict.projectName || "outro projeto"}, de ${startText} até ${endText}.`;
    }
  }

  return null;
}
