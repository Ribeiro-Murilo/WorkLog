import {
  getElapsedDurationSeconds,
  getLatestActivityMs,
  getOccupiedWorkIntervals,
  getRecordedDuration,
  normalizeWorkPeriods,
  startOfLocalDay,
  endOfLocalDayExclusive,
  findNearestFreeInterval
} from "../../src/shared/periods";
import type {
  AvailabilityCheck,
  ConflictInfo,
  Project,
  Session,
  SessionUpdateInput,
  SessionWorkPeriod,
  TimerState
} from "../../src/shared/types";
import {
  VALIDATION_MESSAGES,
  ValidationError,
  validateCycles,
  validateSessionFields
} from "../../src/shared/validation";
import type { ProjectRepository } from "./projectRepository";
import type { SessionRepository } from "./sessionRepository";

export class TimerService {
  private tickTimer: NodeJS.Timeout | null = null;
  private activeSessionId: string | null = null;

  constructor(
    private readonly sessionRepository: SessionRepository,
    private readonly projectRepository: ProjectRepository,
    private readonly onChanged?: () => void
  ) {
    this.restoreActiveSessionIfNeeded();
  }

  private restoreActiveSessionIfNeeded(): void {
    const running = this.sessionRepository.fetchActiveSession();
    if (running) {
      this.activeSessionId = running.id;
      this.startTicking();
    }
  }

  dispose(): void {
    this.stopTicking();
  }

  isRunning(): boolean {
    return this.sessionRepository.fetchActiveSession() !== null;
  }

  state(now: Date = new Date()): TimerState {
    const activeSession = this.sessionRepository.fetchActiveSession();
    this.activeSessionId = activeSession ? activeSession.id : null;
    const activeProject =
      activeSession?.projectId ? this.projectRepository.fetchById(activeSession.projectId) : null;

    const resumable = activeSession ? null : this.resumableSession(null);
    const nowMs = now.getTime();
    const elapsedSeconds = activeSession ? getElapsedDurationSeconds(activeSession, nowMs) : 0;

    const dayStart = startOfLocalDay(now).getTime();
    const dayEnd = endOfLocalDayExclusive(now).getTime();
    const todaySessions = this.sessionRepository.fetchSessionsInInterval(dayStart, dayEnd);
    const todayTotalSeconds = todaySessions.reduce(
      (sum, session) => sum + getRecordedDuration(session, dayStart, dayEnd),
      0
    );

    return {
      activeSession,
      activeProject,
      resumableSession: resumable?.session ?? null,
      resumableProject: resumable?.project ?? null,
      elapsedSeconds,
      isRunning: activeSession !== null,
      todayTotalSeconds
    };
  }

  start(projectId: string, now: Date = new Date()): Session {
    const project = this.projectRepository.fetchById(projectId);
    if (!project) {
      throw new Error("Projeto não encontrado.");
    }
    if (project.isArchived) {
      throw new Error("Não é possível iniciar timer em um projeto arquivado.");
    }

    this.closeCurrentRunningSession("paused", now);

    const nowIso = now.toISOString();
    const session = this.sessionRepository.insert({
      projectId: project.id,
      date: nowIso,
      startTime: nowIso,
      endTime: null,
      durationSeconds: 0,
      workPeriods: [{ start: nowIso, end: null }],
      note: "",
      category: project.category,
      status: "running",
      createdAt: nowIso,
      updatedAt: nowIso
    });

    this.activeSessionId = session.id;
    this.startTicking();
    this.onChanged?.();
    return session;
  }

  pause(now: Date = new Date()): Session | null {
    const closed = this.closeCurrentRunningSession("paused", now);
    this.stopTicking();
    if (closed) {
      this.onChanged?.();
    }
    return closed;
  }

  resumableSession(projectId?: string | null): { session: Session; project: Project } | null {
    let latest: Session | undefined;
    if (projectId) {
      const persistedProject = this.projectRepository.fetchById(projectId);
      if (!persistedProject || persistedProject.isArchived) return null;
      const projectSessions = this.sessionRepository.fetchAll(persistedProject.id);
      latest = projectSessions.sort((a, b) => getLatestActivityMs(b) - getLatestActivityMs(a))[0];
    } else {
      if (this.sessionRepository.fetchActiveSession() !== null) return null;
      const allSessions = this.sessionRepository.fetchAll(null);
      latest = allSessions.sort((a, b) => getLatestActivityMs(b) - getLatestActivityMs(a))[0];
    }

    if (!latest || latest.status !== "paused" || latest.endTime === null || !latest.projectId) {
      return null;
    }
    const persistedProject = this.projectRepository.fetchById(latest.projectId);
    if (!persistedProject || persistedProject.isArchived) return null;

    return { session: latest, project: persistedProject };
  }

  resume(projectId?: string | null, now: Date = new Date()): Session | null {
    const match = this.resumableSession(projectId);
    if (!match) return null;

    const periods = normalizeWorkPeriods(match.session);
    const accumulated = periods.reduce((total, period) => {
      const startMs = Date.parse(period.start);
      const endMs = Date.parse(period.end ?? period.start);
      return total + Math.max(0, (endMs - startMs) / 1000);
    }, 0);

    this.closeCurrentRunningSession("paused", now);

    const nowIso = now.toISOString();
    periods.push({ start: nowIso, end: null });

    const updated = this.sessionRepository.update({
      ...match.session,
      workPeriods: periods,
      durationSeconds: accumulated,
      endTime: null,
      status: "running"
    });

    this.activeSessionId = updated.id;
    this.startTicking();
    this.onChanged?.();
    return updated;
  }

  stop(now: Date = new Date()): Session | null {
    const closed = this.closeCurrentRunningSession("completed", now);
    this.stopTicking();
    if (closed) {
      this.onChanged?.();
    }
    return closed;
  }

  addManualSession(input: {
    projectId: string;
    startTime: string;
    endTime: string;
    note: string;
  }): Session {
    const project = this.projectRepository.fetchById(input.projectId);
    if (!project) {
      throw new ValidationError(VALIDATION_MESSAGES.missingProject);
    }
    validateSessionFields(project.id, input.startTime, input.endTime);

    const startMs = Date.parse(input.startTime);
    const endMs = Date.parse(input.endTime);
    if (this.sessionRepository.hasOverlap(startMs, endMs, null)) {
      throw new ValidationError(VALIDATION_MESSAGES.overlappingSession);
    }

    const session = this.sessionRepository.insert({
      projectId: project.id,
      date: startOfLocalDay(new Date(startMs)).toISOString(),
      startTime: input.startTime,
      endTime: input.endTime,
      durationSeconds: (endMs - startMs) / 1000,
      workPeriods: [{ start: input.startTime, end: input.endTime }],
      note: input.note,
      category: project.category,
      status: "completed"
    });
    this.onChanged?.();
    return session;
  }

  updateSession(sessionId: string, input: SessionUpdateInput): Session {
    const persisted = this.sessionRepository.fetchById(sessionId);
    if (!persisted) {
      throw new Error("Esta sessão foi removida. Feche o formulário e atualize a lista.");
    }
    if (persisted.status === "running") {
      throw new Error("Pause ou encerre o timer antes de editar esta sessão.");
    }

    if (input.expectedStatus && persisted.status !== input.expectedStatus) {
      throw new Error(
        "Os ciclos desta sessão foram alterados. Reabra a edição para carregar os horários atuais."
      );
    }
    if (input.expectedWorkPeriods) {
      const currentNorm = JSON.stringify(normalizeWorkPeriods(persisted));
      const expectedNorm = JSON.stringify(input.expectedWorkPeriods);
      if (currentNorm !== expectedNorm) {
        throw new Error(
          "Os ciclos desta sessão foram alterados. Reabra a edição para carregar os horários atuais."
        );
      }
    }

    if (input.workPeriods && input.workPeriods.length > 1) {
      const cycleError = this.validateCyclesAgainstRepo(input.workPeriods, persisted.id);
      if (cycleError) {
        throw new ValidationError(cycleError);
      }
      const first = input.workPeriods[0];
      const last = input.workPeriods[input.workPeriods.length - 1];
      if (!first || !last.end) {
        throw new ValidationError(VALIDATION_MESSAGES.invalidDateRange);
      }
      const totalSeconds = input.workPeriods.reduce((acc, period) => {
        const s = Date.parse(period.start);
        const e = Date.parse(period.end ?? period.start);
        return acc + Math.max(0, (e - s) / 1000);
      }, 0);

      const updated = this.sessionRepository.update({
        ...persisted,
        date: startOfLocalDay(new Date(Date.parse(first.start))).toISOString(),
        startTime: first.start,
        endTime: last.end,
        durationSeconds: totalSeconds,
        workPeriods: input.workPeriods,
        note: input.note
      });
      this.onChanged?.();
      return updated;
    }

    validateSessionFields(persisted.projectId, input.startTime, input.endTime);
    const startMs = Date.parse(input.startTime);
    const endMs = Date.parse(input.endTime);
    if (this.sessionRepository.hasOverlap(startMs, endMs, persisted.id)) {
      throw new ValidationError(VALIDATION_MESSAGES.overlappingSession);
    }

    const updated = this.sessionRepository.update({
      ...persisted,
      date: startOfLocalDay(new Date(startMs)).toISOString(),
      startTime: input.startTime,
      endTime: input.endTime,
      durationSeconds: (endMs - startMs) / 1000,
      workPeriods: persisted.workPeriods
        ? [{ start: input.startTime, end: input.endTime }]
        : null,
      note: input.note
    });
    this.onChanged?.();
    return updated;
  }

  checkAvailability(params: {
    startTime: string;
    endTime: string;
    excludingSessionId?: string | null;
    workPeriods?: SessionWorkPeriod[];
  }): AvailabilityCheck {
    if (params.workPeriods && params.workPeriods.length > 1) {
      const conflicts: ConflictInfo[] = [];
      const cycleProblem = validateCycles(params.workPeriods, (startMs, endMs) => {
        const found = this.sessionRepository.conflictingSessions(
          startMs,
          endMs,
          params.excludingSessionId
        );
        if (found.length === 0) return null;
        for (const item of found) {
          conflicts.push(this.toConflictInfo(item));
        }
        const first = found[0];
        const project = first.projectId ? this.projectRepository.fetchById(first.projectId) : null;
        const busy = getOccupiedWorkIntervals(first).find(
          (iv) => iv.startMs < endMs && iv.endMs > startMs
        );
        return {
          projectName: project?.name ?? "outro projeto",
          intervalStartIso: new Date(busy?.startMs ?? Date.parse(first.startTime)).toISOString(),
          intervalEndIso:
            busy && Number.isFinite(busy.endMs)
              ? new Date(busy.endMs).toISOString()
              : first.endTime
        };
      });
      return { conflicts, suggestedInterval: null, cycleProblem };
    }

    const startMs = Date.parse(params.startTime);
    const endMs = Date.parse(params.endTime);
    if (!Number.isFinite(startMs) || !Number.isFinite(endMs) || endMs <= startMs) {
      return { conflicts: [], suggestedInterval: null, cycleProblem: null };
    }

    const conflicting = this.sessionRepository.conflictingSessions(
      startMs,
      endMs,
      params.excludingSessionId
    );
    if (conflicting.length === 0) {
      return { conflicts: [], suggestedInterval: null, cycleProblem: null };
    }

    const occupied = this.sessionRepository
      .fetchAll(null)
      .filter((s) => s.id !== params.excludingSessionId)
      .flatMap((s) => getOccupiedWorkIntervals(s));
    const nearest = findNearestFreeInterval(startMs, endMs, occupied);

    return {
      conflicts: conflicting.map((s) => this.toConflictInfo(s)),
      suggestedInterval: nearest
        ? {
            start: new Date(nearest.startMs).toISOString(),
            end: new Date(nearest.endMs).toISOString()
          }
        : null,
      cycleProblem: null
    };
  }

  private toConflictInfo(session: Session): ConflictInfo {
    const project = session.projectId ? this.projectRepository.fetchById(session.projectId) : null;
    return {
      sessionId: session.id,
      projectName: project?.name ?? "Projeto removido",
      intervals: getOccupiedWorkIntervals(session).map((iv) => ({
        start: new Date(iv.startMs).toISOString(),
        end: Number.isFinite(iv.endMs) ? new Date(iv.endMs).toISOString() : null
      }))
    };
  }

  private validateCyclesAgainstRepo(periods: SessionWorkPeriod[], excludingSessionId: string): string | null {
    return validateCycles(periods, (startMs, endMs) => {
      const conflicts = this.sessionRepository.conflictingSessions(
        startMs,
        endMs,
        excludingSessionId
      );
      const conflict = conflicts[0];
      if (!conflict) return null;
      const project = conflict.projectId
        ? this.projectRepository.fetchById(conflict.projectId)
        : null;
      const busy = getOccupiedWorkIntervals(conflict).find(
        (iv) => iv.startMs < endMs && iv.endMs > startMs
      );
      return {
        projectName: project?.name ?? "outro projeto",
        intervalStartIso: new Date(busy?.startMs ?? Date.parse(conflict.startTime)).toISOString(),
        intervalEndIso:
          busy && Number.isFinite(busy.endMs)
            ? new Date(busy.endMs).toISOString()
            : conflict.endTime
      };
    });
  }

  private closeCurrentRunningSession(status: "paused" | "completed", now: Date): Session | null {
    const session =
      this.sessionRepository.fetchActiveSession() ??
      (this.activeSessionId ? this.sessionRepository.fetchById(this.activeSessionId) : null);
    if (!session || session.status !== "running") return null;

    const nowMs = now.getTime();
    const periods = normalizeWorkPeriods(session).map((period) => {
      if (period.end !== null) return period;
      const startMs = Date.parse(period.start);
      return {
        start: period.start,
        end: new Date(Math.max(nowMs, startMs)).toISOString()
      };
    });

    const totalSeconds = periods.reduce((sum, period) => {
      const startMs = Date.parse(period.start);
      const endMs = Date.parse(period.end ?? period.start);
      return sum + Math.max(0, (endMs - startMs) / 1000);
    }, 0);

    const updated = this.sessionRepository.update({
      ...session,
      workPeriods: periods,
      endTime: now.toISOString(),
      durationSeconds: totalSeconds,
      status
    });
    this.activeSessionId = null;
    return updated;
  }

  private startTicking(): void {
    this.stopTicking();
    this.tickTimer = setInterval(() => {
      if (!this.sessionRepository.fetchActiveSession()) {
        this.stopTicking();
        return;
      }
      this.onChanged?.();
    }, 1000);
  }

  private stopTicking(): void {
    if (this.tickTimer) {
      clearInterval(this.tickTimer);
      this.tickTimer = null;
    }
  }
}
