import { describe, expect, it } from "vitest";
import { openDatabase } from "../electron/data/database";
import { ProjectRepository } from "../electron/services/projectRepository";
import { SessionRepository } from "../electron/services/sessionRepository";
import { TimerService } from "../electron/services/timerService";
import { VALIDATION_MESSAGES } from "../src/shared/validation";

function setup() {
  const db = openDatabase(":memory:");
  const projects = new ProjectRepository(db);
  const sessions = new SessionRepository(db);
  const timer = new TimerService(sessions, projects);
  return { db, projects, sessions, timer };
}

describe("timerAndRepos", () => {
  it("valida campos e impede projeto duplicado (nome + cliente)", () => {
    const { db, projects, timer } = setup();
    const p1 = projects.insert({
      name: "Portal",
      client: "ACME",
      dailyRate: 800,
      category: "work",
      tags: ["web"],
      descriptionText: "",
      status: "active"
    });
    expect(p1.name).toBe("Portal");

    expect(() =>
      projects.insert({
        name: "Portal",
        client: "ACME",
        dailyRate: 800,
        category: "work",
        tags: [],
        descriptionText: "",
        status: "active"
      })
    ).toThrow(VALIDATION_MESSAGES.duplicateProject);

    expect(() =>
      projects.insert({
        name: "  ",
        client: "ACME",
        dailyRate: 100,
        category: "work",
        tags: [],
        descriptionText: "",
        status: "active"
      })
    ).toThrow(VALIDATION_MESSAGES.emptyName);

    timer.dispose();
    db.close();
  });

  it("retoma na mesma sessão acumulando múltiplos ciclos e bloqueia retomada após concluir ou arquivar", () => {
    const { db, projects, sessions, timer } = setup();
    const proj = projects.insert({
      name: "App Mobile",
      client: "Cliente A",
      dailyRate: 800,
      category: "work",
      tags: [],
      descriptionText: "",
      status: "active"
    });

    const t0 = new Date("2026-10-10T09:00:00.000Z");
    const t1 = new Date("2026-10-10T09:30:00.000Z");
    const t2 = new Date("2026-10-10T10:00:00.000Z");
    const t3 = new Date("2026-10-10T10:15:00.000Z");

    const started = timer.start(proj.id, t0);
    timer.pause(t1);
    const resumed = timer.resume(null, t2);
    expect(resumed).not.toBeNull();
    expect(resumed!.id).toBe(started.id);

    const stopped = timer.stop(t3);
    expect(stopped!.status).toBe("completed");
    expect(stopped!.durationSeconds).toBe(2700); // 30m + 15m
    expect(stopped!.workPeriods).toHaveLength(2);
    expect(sessions.fetchAll(proj.id)).toHaveLength(1);

    // Concluída não pode ser retomada
    expect(timer.resumableSession(null)).toBeNull();
    expect(timer.resumableSession(proj.id)).toBeNull();

    // Pausada em projeto arquivado não pode ser retomada
    timer.start(proj.id, new Date("2026-10-10T11:00:00.000Z"));
    timer.pause(new Date("2026-10-10T11:10:00.000Z"));
    expect(timer.resumableSession(proj.id)).not.toBeNull();
    projects.archive(proj.id, true);
    expect(timer.resumableSession(proj.id)).toBeNull();
    expect(timer.resumableSession(null)).toBeNull();

    timer.dispose();
    db.close();
  });

  it("valida edição multi-ciclo e bloqueia sessão em execução", () => {
    const { db, projects, timer } = setup();
    const proj = projects.insert({
      name: "Backend",
      client: "Cliente B",
      dailyRate: 800,
      category: "work",
      tags: [],
      descriptionText: "",
      status: "active"
    });

    const s1 = timer.start(proj.id, new Date("2026-10-10T09:00:00.000Z"));
    expect(() =>
      timer.updateSession(s1.id, {
        startTime: "2026-10-10T09:00:00.000Z",
        endTime: "2026-10-10T09:30:00.000Z",
        note: ""
      })
    ).toThrow("Pause ou encerre");

    timer.pause(new Date("2026-10-10T09:30:00.000Z"));
    timer.resume(null, new Date("2026-10-10T10:00:00.000Z"));
    const finished = timer.stop(new Date("2026-10-10T10:30:00.000Z"))!;

    // Ordem inválida entre ciclo 1 e ciclo 2 deve falhar
    expect(() =>
      timer.updateSession(finished.id, {
        startTime: finished.startTime,
        endTime: finished.endTime!,
        note: "",
        workPeriods: [
          { start: "2026-10-10T09:00:00.000Z", end: "2026-10-10T10:05:00.000Z" },
          { start: "2026-10-10T10:00:00.000Z", end: "2026-10-10T10:30:00.000Z" }
        ]
      })
    ).toThrow("Ciclo 2");

    // Atualização válida de ciclos soma apenas tempo trabalhado
    const updated = timer.updateSession(finished.id, {
      startTime: finished.startTime,
      endTime: finished.endTime!,
      note: "ajustado",
      workPeriods: [
        { start: "2026-10-10T09:00:00.000Z", end: "2026-10-10T09:45:00.000Z" },
        { start: "2026-10-10T10:00:00.000Z", end: "2026-10-10T10:15:00.000Z" }
      ]
    });
    expect(updated.durationSeconds).toBe(3600);
    expect(updated.note).toBe("ajustado");

    timer.dispose();
    db.close();
  });
});
