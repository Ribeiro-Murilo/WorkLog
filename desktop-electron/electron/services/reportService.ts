import type { DashboardSummary, Session, SummaryBucket } from "../../src/shared/types";
import { ProjectRepository } from "./projectRepository";
import { SessionRepository } from "./sessionRepository";

const STANDARD_WORKDAY_HOURS = 8;

export class ReportService {
  constructor(
    private readonly projects: ProjectRepository,
    private readonly sessions: SessionRepository
  ) {}

  dashboardSummary(): DashboardSummary {
    const projects = this.projects.fetchAll(true);
    const sessions = this.sessions.fetchAll();
    const closedSessions = sessions.filter((session) => session.status !== "running");
    const projectById = new Map(projects.map((project) => [project.id, project]));
    const now = new Date();
    const todayStart = startOfDay(now);
    const weekStart = startOfWeek(now);
    const monthStart = new Date(now.getFullYear(), now.getMonth(), 1);

    return {
      todaySeconds: sumSince(closedSessions, todayStart),
      weekSeconds: sumSince(closedSessions, weekStart),
      monthSeconds: sumSince(closedSessions, monthStart),
      totalSeconds: sumSeconds(closedSessions),
      activeProjects: projects.filter((project) => !project.isArchived).length,
      archivedProjects: projects.filter((project) => project.isArchived).length,
      totalValue: closedSessions.reduce((total, session) => total + estimatedValue(session, projectById), 0),
      byProject: groupSessions(closedSessions, (session) => session.projectName || "Sem projeto", projectById),
      byClient: groupSessions(closedSessions, (session) => session.projectClient || "Sem cliente", projectById),
      byCategory: groupSessions(closedSessions, (session) => (session.category === "work" ? "Trabalho" : "Pessoal"), projectById),
      recentSessions: this.sessions.fetchRecent(8)
    };
  }
}

function sumSince(sessions: Session[], start: Date): number {
  return sumSeconds(sessions.filter((session) => new Date(session.startTime) >= start));
}

function sumSeconds(sessions: Session[]): number {
  return sessions.reduce((total, session) => total + session.durationSeconds, 0);
}

function groupSessions(
  sessions: Session[],
  labelFor: (session: Session) => string,
  projectById: Map<string, { dailyRate: number }>
): SummaryBucket[] {
  const buckets = new Map<string, SummaryBucket>();
  for (const session of sessions) {
    const label = labelFor(session);
    const current = buckets.get(label) ?? { label, seconds: 0, value: 0 };
    current.seconds += session.durationSeconds;
    current.value += estimatedValue(session, projectById);
    buckets.set(label, current);
  }
  return [...buckets.values()].sort((a, b) => b.seconds - a.seconds).slice(0, 8);
}

function estimatedValue(session: Session, projectById: Map<string, { dailyRate: number }>): number {
  if (!session.projectId) return 0;
  const project = projectById.get(session.projectId);
  if (!project?.dailyRate) return 0;
  const hours = session.durationSeconds / 3600;
  return project.dailyRate * (hours / STANDARD_WORKDAY_HOURS);
}

function startOfDay(date: Date): Date {
  return new Date(date.getFullYear(), date.getMonth(), date.getDate());
}

function startOfWeek(date: Date): Date {
  const day = date.getDay();
  const diff = day === 0 ? 6 : day - 1;
  const start = startOfDay(date);
  start.setDate(start.getDate() - diff);
  return start;
}
