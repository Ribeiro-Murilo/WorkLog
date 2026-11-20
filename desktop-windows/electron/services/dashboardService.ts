import {
  calculateSessionValue,
  getRecordedDuration,
  normalizeWorkPeriods,
  resolveReportPeriod
} from "../../src/shared/periods";
import type {
  DashboardSummary,
  Project,
  ProjectCategory,
  ProjectWithStats,
  Session,
  SessionWithProject
} from "../../src/shared/types";
import type { ProjectRepository } from "./projectRepository";
import type { SessionRepository } from "./sessionRepository";

export class DashboardService {
  constructor(
    private readonly projectRepository: ProjectRepository,
    private readonly sessionRepository: SessionRepository
  ) {}

  enrichSessions(sessions: Session[], projectsById: Map<string, Project>): SessionWithProject[] {
    return sessions.map((session) => {
      const project = session.projectId ? projectsById.get(session.projectId) : undefined;
      return {
        ...session,
        projectName: project?.name ?? "—",
        projectClient: project?.client ?? "—",
        normalizedPeriods: normalizeWorkPeriods(session)
      };
    });
  }

  enrichProjects(projects: Project[], allSessions: Session[]): ProjectWithStats[] {
    const sessionsByProject = new Map<string, Session[]>();
    for (const session of allSessions) {
      if (!session.projectId) continue;
      const list = sessionsByProject.get(session.projectId) ?? [];
      list.push(session);
      sessionsByProject.set(session.projectId, list);
    }

    return projects.map((project) => {
      const list = sessionsByProject.get(project.id) ?? [];
      let totalWorkedSeconds = 0;
      let totalValue = 0;
      for (const session of list) {
        if (session.status === "running") {
          const rec = getRecordedDuration(session);
          totalWorkedSeconds += rec;
          totalValue += calculateSessionValue(rec, project.dailyRate);
        } else {
          totalWorkedSeconds += session.durationSeconds;
          totalValue += calculateSessionValue(session.durationSeconds, project.dailyRate);
        }
      }
      return {
        ...project,
        totalWorkedSeconds,
        totalValue,
        sessionCount: list.length
      };
    });
  }

  summary(referenceDate: Date = new Date()): DashboardSummary {
    const allProjects = this.projectRepository.fetchAll(true);
    const projectsById = new Map(allProjects.map((p) => [p.id, p]));
    const activeProjectsCount = allProjects.filter((p) => !p.isArchived).length;
    const archivedProjectsCount = allProjects.filter((p) => p.isArchived).length;

    const allSessions = this.sessionRepository.fetchAll(null);
    const allTimeTotal = allSessions.reduce((acc, s) => acc + getRecordedDuration(s), 0);

    const dayInterval = resolveReportPeriod("today", "", "", referenceDate);
    const weekInterval = resolveReportPeriod("week", "", "", referenceDate);
    const monthInterval = resolveReportPeriod("month", "", "", referenceDate);

    const todayTotal = allSessions.reduce(
      (acc, s) => acc + getRecordedDuration(s, dayInterval.startMs, dayInterval.endMs),
      0
    );
    const weekTotal = allSessions.reduce(
      (acc, s) => acc + getRecordedDuration(s, weekInterval.startMs, weekInterval.endMs),
      0
    );
    const monthTotal = allSessions.reduce(
      (acc, s) => acc + getRecordedDuration(s, monthInterval.startMs, monthInterval.endMs),
      0
    );

    const recentSessions = this.enrichSessions(allSessions.slice(0, 10), projectsById);

    const byProject = new Map<string, number>();
    const byCategory = new Map<ProjectCategory, number>();
    const byClient = new Map<string, number>();

    for (const session of allSessions) {
      const dur = getRecordedDuration(session);
      if (session.projectId && projectsById.has(session.projectId)) {
        byProject.set(session.projectId, (byProject.get(session.projectId) ?? 0) + dur);
      }
      byCategory.set(session.category, (byCategory.get(session.category) ?? 0) + dur);
      const client = (session.projectId && projectsById.get(session.projectId)?.client) || "—";
      byClient.set(client, (byClient.get(client) ?? 0) + dur);
    }

    const projectUsage = Array.from(byProject.entries())
      .map(([projectId, total]) => ({ project: projectsById.get(projectId)!, total }))
      .sort((a, b) => b.total - a.total);

    const timeByCategory = Array.from(byCategory.entries())
      .map(([category, total]) => ({ category, total }))
      .sort((a, b) => b.total - a.total);

    const timeByClient = Array.from(byClient.entries())
      .map(([client, total]) => ({ client, total }))
      .sort((a, b) => b.total - a.total);

    return {
      todayTotal,
      weekTotal,
      monthTotal,
      allTimeTotal,
      activeProjectsCount,
      archivedProjectsCount,
      recentSessions,
      mostUsedProjects: projectUsage,
      timeByCategory,
      timeByClient,
      timeByProject: projectUsage
    };
  }
}
