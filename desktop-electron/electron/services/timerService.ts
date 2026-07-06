import { BrowserWindow, powerMonitor } from "electron";
import type { Project, Session, SessionInput, TimerState } from "../../src/shared/types";
import { secondsBetween } from "../../src/shared/format";
import { validateSessionFields } from "../../src/shared/validation";
import { ProjectRepository } from "./projectRepository";
import { SessionRepository } from "./sessionRepository";
import { SettingsRepository } from "./settingsRepository";

export class TimerService {
  private tick: NodeJS.Timeout | null = null;

  constructor(
    private readonly projects: ProjectRepository,
    private readonly sessions: SessionRepository,
    private readonly settings: SettingsRepository,
    private readonly broadcast: () => void
  ) {
    powerMonitor.on("suspend", () => {
      this.pause().catch(() => undefined);
    });
    powerMonitor.on("lock-screen", () => {
      this.pause().catch(() => undefined);
    });
    setInterval(() => {
      const active = this.sessions.fetchActive();
      const idleLimit = this.settings.get().idleTimeoutMinutes * 60;
      if (active && powerMonitor.getSystemIdleTime() >= idleLimit) {
        this.pause().catch(() => undefined);
      }
    }, 30_000);
  }

  state(): TimerState {
    const activeSession = this.sessions.fetchActive();
    const activeProject = activeSession?.projectId ? this.projects.fetchById(activeSession.projectId) : null;
    const elapsedSeconds = activeSession ? secondsBetween(activeSession.startTime, new Date().toISOString()) : 0;
    this.ensureTick(Boolean(activeSession));
    return {
      activeSession,
      activeProject,
      elapsedSeconds,
      isRunning: Boolean(activeSession)
    };
  }

  async start(projectId: string): Promise<TimerState> {
    const project = this.projects.fetchById(projectId);
    if (!project) throw new Error("Projeto não encontrado.");
    this.closeCurrentRunningSession("paused");
    this.sessions.insert({
      projectId: project.id,
      date: new Date().toISOString(),
      startTime: new Date().toISOString(),
      endTime: null,
      durationSeconds: 0,
      note: "",
      category: project.category,
      status: "running"
    });
    this.broadcast();
    return this.state();
  }

  async pause(): Promise<TimerState> {
    this.closeCurrentRunningSession("paused");
    this.broadcast();
    return this.state();
  }

  async stop(): Promise<TimerState> {
    this.closeCurrentRunningSession("completed");
    this.broadcast();
    return this.state();
  }

  async resume(): Promise<TimerState> {
    const recent = this.sessions.fetchRecent(1)[0];
    if (!recent?.projectId) return this.state();
    return this.start(recent.projectId);
  }

  addManualSession(input: SessionInput): Session {
    const project = this.projects.fetchById(input.projectId);
    validateSessionFields(project, input);
    if (this.sessions.hasOverlap(input.startTime, input.endTime, null)) {
      throw new Error("Já existe uma sessão registrada nesse período.");
    }
    const session = this.sessions.insert({
      projectId: input.projectId,
      date: input.startTime,
      startTime: input.startTime,
      endTime: input.endTime,
      durationSeconds: secondsBetween(input.startTime, input.endTime),
      note: input.note.trim(),
      category: (project as Project).category,
      status: "completed"
    });
    this.broadcast();
    return session;
  }

  updateManualSession(id: string, input: SessionInput): Session {
    const project = this.projects.fetchById(input.projectId);
    validateSessionFields(project, input);
    if (this.sessions.hasOverlap(input.startTime, input.endTime, id)) {
      throw new Error("Já existe uma sessão registrada nesse período.");
    }
    const session = this.sessions.update(id, {
      projectId: input.projectId,
      date: input.startTime,
      startTime: input.startTime,
      endTime: input.endTime,
      durationSeconds: secondsBetween(input.startTime, input.endTime),
      note: input.note.trim(),
      category: (project as Project).category,
      status: "completed"
    });
    this.broadcast();
    return session;
  }

  registerWindow(window: BrowserWindow): void {
    window.on("closed", () => {
      if (this.tick && BrowserWindow.getAllWindows().length === 0) {
        clearInterval(this.tick);
        this.tick = null;
      }
    });
  }

  private closeCurrentRunningSession(status: "paused" | "completed"): void {
    const active = this.sessions.fetchActive();
    if (!active) return;
    const now = new Date().toISOString();
    this.sessions.update(active.id, {
      endTime: now,
      durationSeconds: secondsBetween(active.startTime, now),
      status
    });
  }

  private ensureTick(shouldRun: boolean): void {
    if (!shouldRun && this.tick) {
      clearInterval(this.tick);
      this.tick = null;
      return;
    }
    if (shouldRun && !this.tick) {
      this.tick = setInterval(this.broadcast, 1000);
    }
  }
}
