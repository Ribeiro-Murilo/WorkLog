import { describe, expect, it } from "vitest";
import {
  calculateSessionValue,
  findNearestFreeInterval,
  getElapsedDurationSeconds,
  getOccupiedWorkIntervals,
  getRecordedSlices,
  normalizeWorkPeriods
} from "../src/shared/periods";
import type { Session } from "../src/shared/types";

function makeSession(overrides: Partial<Session>): Session {
  return {
    id: "S1",
    projectId: "P1",
    date: "2026-10-10T10:00:00.000Z",
    startTime: "2026-10-10T10:00:00.000Z",
    endTime: "2026-10-10T11:00:00.000Z",
    durationSeconds: 3600,
    workPeriods: null,
    note: "",
    category: "work",
    status: "completed",
    createdAt: "2026-10-10T10:00:00.000Z",
    updatedAt: "2026-10-10T11:00:00.000Z",
    ...overrides
  };
}

describe("periods", () => {
  it("mantém pausas entre ciclos livres de conflito", () => {
    const s = makeSession({
      startTime: "2026-10-10T09:00:00.000Z",
      endTime: "2026-10-10T12:00:00.000Z",
      durationSeconds: 7200,
      workPeriods: [
        { start: "2026-10-10T09:00:00.000Z", end: "2026-10-10T10:00:00.000Z" },
        { start: "2026-10-10T11:00:00.000Z", end: "2026-10-10T12:00:00.000Z" }
      ]
    });

    const occupied = getOccupiedWorkIntervals(s);
    expect(occupied).toHaveLength(2);
    expect(occupied[0].endMs).toBe(Date.parse("2026-10-10T10:00:00.000Z"));
    expect(occupied[1].startMs).toBe(Date.parse("2026-10-10T11:00:00.000Z"));
  });

  it("divide trechos que atravessam a meia-noite local", () => {
    const start = new Date(2026, 9, 10, 23, 0, 0);
    const end = new Date(2026, 9, 11, 1, 0, 0);
    const s = makeSession({
      startTime: start.toISOString(),
      endTime: end.toISOString(),
      durationSeconds: 7200,
      workPeriods: [{ start: start.toISOString(), end: end.toISOString() }]
    });

    const slices = getRecordedSlices(s);
    expect(slices).toHaveLength(2);
    expect(slices[0].durationSeconds).toBe(3600);
    expect(slices[1].durationSeconds).toBe(3600);
  });

  it("soma tempo decorrido durante sessão retomada em execução", () => {
    const t0 = Date.parse("2026-10-10T10:00:00.000Z");
    const s = makeSession({
      status: "running",
      endTime: null,
      durationSeconds: 1800,
      workPeriods: [
        { start: "2026-10-10T09:00:00.000Z", end: "2026-10-10T09:30:00.000Z" },
        { start: "2026-10-10T10:00:00.000Z", end: null }
      ]
    });
    expect(getElapsedDurationSeconds(s, t0 + 120_000)).toBe(1920);
  });

  it("sugere intervalo livre mais próximo desempatando pelo horário posterior", () => {
    const busyStart = new Date(2026, 9, 10, 10, 0, 0).getTime();
    const busyEnd = new Date(2026, 9, 10, 11, 0, 0).getTime();

    // Pedido exatamente sobre [10:00, 11:00]: distância é 1h para 09:00-10:00 ou 1h para 11:00-12:00
    const suggestion = findNearestFreeInterval(busyStart, busyEnd, [
      { startMs: busyStart, endMs: busyEnd }
    ]);
    expect(suggestion).not.toBeNull();
    expect(suggestion!.startMs).toBe(busyEnd);
    expect(suggestion!.endMs).toBe(busyEnd + 3600_000);
  });

  it("retorna null quando não cabe no dia por causa de sessão cruzando meia-noite", () => {
    const prevNight = new Date(2026, 9, 9, 22, 0, 0).getTime();
    const nextNight = new Date(2026, 9, 11, 2, 0, 0).getTime();
    const reqStart = new Date(2026, 9, 10, 9, 0, 0).getTime();
    const reqEnd = new Date(2026, 9, 10, 10, 0, 0).getTime();

    expect(
      findNearestFreeInterval(reqStart, reqEnd, [{ startMs: prevNight, endMs: nextNight }])
    ).toBeNull();
  });

  it("calcula valor da sessão com jornada padrão de 8h e normaliza legado", () => {
    expect(calculateSessionValue(4 * 3600, 800)).toBeCloseTo(400);
    const legacy = makeSession({
      startTime: "2026-10-10T09:00:00.000Z",
      endTime: "2026-10-10T11:00:00.000Z",
      durationSeconds: 3600,
      workPeriods: null
    });
    const norm = normalizeWorkPeriods(legacy);
    expect(norm[0].start).toBe("2026-10-10T10:00:00.000Z");
  });
});
