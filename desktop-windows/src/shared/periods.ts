import {
  STANDARD_WORKDAY_HOURS,
  type ReportPeriod,
  type Session,
  type SessionWorkPeriod
} from "./types";

export interface NumericInterval {
  startMs: number;
  endMs: number;
}

export interface RecordedSlice {
  startMs: number;
  endMs: number;
  durationSeconds: number;
}

export function startOfLocalDay(date: Date): Date {
  return new Date(date.getFullYear(), date.getMonth(), date.getDate(), 0, 0, 0, 0);
}

export function endOfLocalDayExclusive(date: Date): Date {
  return new Date(date.getFullYear(), date.getMonth(), date.getDate() + 1, 0, 0, 0, 0);
}

export function normalizeWorkPeriods(session: Pick<Session, "startTime" | "endTime" | "durationSeconds" | "status" | "workPeriods">): SessionWorkPeriod[] {
  if (session.workPeriods && session.workPeriods.length > 0) {
    return session.workPeriods.map((p) => ({ start: p.start, end: p.end }));
  }
  if (session.status === "running") {
    return [{ start: session.startTime, end: null }];
  }
  const startMs = Date.parse(session.startTime);
  const computedEndMs = session.endTime
    ? Date.parse(session.endTime)
    : startMs + Math.max(0, session.durationSeconds) * 1000;
  const endIso = new Date(computedEndMs).toISOString();
  const diffSeconds = (computedEndMs - startMs) / 1000;
  const legacyStartIso =
    session.durationSeconds > 0 && Math.abs(diffSeconds - session.durationSeconds) > 0.001
      ? new Date(computedEndMs - session.durationSeconds * 1000).toISOString()
      : session.startTime;
  return [{ start: legacyStartIso, end: endIso }];
}

export function getLatestActivityMs(session: Pick<Session, "startTime" | "endTime" | "durationSeconds" | "status" | "workPeriods">): number {
  const periods = normalizeWorkPeriods(session);
  let maxMs = Date.parse(session.startTime);
  for (const period of periods) {
    const candidate = Date.parse(period.end ?? period.start);
    if (candidate > maxMs) maxMs = candidate;
  }
  return maxMs;
}

export function getElapsedDurationSeconds(
  session: Pick<Session, "startTime" | "endTime" | "durationSeconds" | "status" | "workPeriods">,
  nowMs: number = Date.now()
): number {
  if (session.status !== "running") return Math.max(0, session.durationSeconds);
  const periods = normalizeWorkPeriods(session);
  let openSeconds = 0;
  for (const period of periods) {
    if (period.end === null) {
      openSeconds += Math.max(0, (nowMs - Date.parse(period.start)) / 1000);
    }
  }
  return Math.max(0, session.durationSeconds) + openSeconds;
}

export function getOccupiedWorkIntervals(
  session: Pick<Session, "startTime" | "endTime" | "durationSeconds" | "status" | "workPeriods">
): NumericInterval[] {
  if (!session.workPeriods || session.workPeriods.length === 0) {
    const startMs = Date.parse(session.startTime);
    const endMs = session.endTime ? Date.parse(session.endTime) : Number.POSITIVE_INFINITY;
    return endMs > startMs ? [{ startMs, endMs }] : [];
  }
  const result: NumericInterval[] = [];
  for (const period of session.workPeriods) {
    const startMs = Date.parse(period.start);
    const endMs = period.end ? Date.parse(period.end) : Number.POSITIVE_INFINITY;
    if (endMs > startMs) {
      result.push({ startMs, endMs });
    }
  }
  return result;
}

export function getRecordedSlices(
  session: Pick<Session, "startTime" | "endTime" | "durationSeconds" | "status" | "workPeriods">,
  intervalStartMs: number = Number.NEGATIVE_INFINITY,
  intervalEndMs: number = Number.POSITIVE_INFINITY
): RecordedSlice[] {
  let periods: SessionWorkPeriod[];
  let scale = 1;

  if (!session.workPeriods || session.workPeriods.length === 0) {
    if (session.status === "running" || !session.endTime) return [];
    const startMs = Date.parse(session.startTime);
    const endMs = Date.parse(session.endTime);
    if (!(endMs > startMs)) return [];
    periods = [{ start: session.startTime, end: session.endTime }];
    scale = Math.max(0, session.durationSeconds) / ((endMs - startMs) / 1000);
  } else {
    periods = session.workPeriods;
  }

  const slices: RecordedSlice[] = [];
  for (const period of periods) {
    if (!period.end) continue;
    let cursor = Math.max(Date.parse(period.start), intervalStartMs);
    const limit = Math.min(Date.parse(period.end), intervalEndMs);
    while (cursor < limit) {
      const nextDayEnd = endOfLocalDayExclusive(new Date(cursor)).getTime();
      const sliceEnd = Math.min(limit, nextDayEnd);
      if (sliceEnd <= cursor) break;
      const duration = ((sliceEnd - cursor) / 1000) * scale;
      if (duration > 0) {
        slices.push({ startMs: cursor, endMs: sliceEnd, durationSeconds: duration });
      }
      cursor = sliceEnd;
    }
  }
  return slices;
}

export function getRecordedDuration(
  session: Pick<Session, "startTime" | "endTime" | "durationSeconds" | "status" | "workPeriods">,
  intervalStartMs: number = Number.NEGATIVE_INFINITY,
  intervalEndMs: number = Number.POSITIVE_INFINITY
): number {
  return getRecordedSlices(session, intervalStartMs, intervalEndMs).reduce(
    (sum, slice) => sum + slice.durationSeconds,
    0
  );
}

export function calculateSessionValue(durationSeconds: number, dailyRate: number): number {
  if (!(dailyRate > 0) || !(durationSeconds > 0)) return 0;
  return dailyRate * (durationSeconds / 3600 / STANDARD_WORKDAY_HOURS);
}

export function intervalsOverlap(aStartMs: number, aEndMs: number, bStartMs: number, bEndMs: number): boolean {
  return aStartMs < bEndMs && aEndMs > bStartMs;
}

/**
 * Port exato de `SessionAvailability.nearestInterval`:
 * encontra o intervalo livre mais próximo no dia calendário de `startMs`,
 * preservando a duração. Em empate de distância, prefere o intervalo posterior.
 */
export function findNearestFreeInterval(
  startMs: number,
  endMs: number,
  occupied: NumericInterval[]
): NumericInterval | null {
  const durationMs = endMs - startMs;
  if (!(durationMs > 0) || !Number.isFinite(durationMs)) return null;

  const dayStart = startOfLocalDay(new Date(startMs)).getTime();
  const dayEnd = endOfLocalDayExclusive(new Date(startMs)).getTime();
  if (durationMs > dayEnd - dayStart) return null;

  const busy = occupied
    .map((item) => ({
      startMs: Math.max(item.startMs, dayStart),
      endMs: Math.min(item.endMs, dayEnd)
    }))
    .filter((item) => item.endMs > item.startMs)
    .sort((a, b) => a.startMs - b.startMs);

  let cursor = dayStart;
  const gaps: NumericInterval[] = [];
  for (const item of busy) {
    if (item.startMs > cursor) {
      gaps.push({ startMs: cursor, endMs: item.startMs });
    }
    cursor = Math.max(cursor, item.endMs);
  }
  if (cursor < dayEnd) {
    gaps.push({ startMs: cursor, endMs: dayEnd });
  }

  const candidates = gaps
    .filter((gap) => gap.endMs - gap.startMs >= durationMs)
    .map((gap) => {
      const latestStart = gap.endMs - durationMs;
      const candidateStart = Math.min(Math.max(startMs, gap.startMs), latestStart);
      return { startMs: candidateStart, endMs: candidateStart + durationMs };
    });

  if (candidates.length === 0) return null;

  return candidates.reduce((best, current) => {
    const bestDist = Math.abs(best.startMs - startMs);
    const currDist = Math.abs(current.startMs - startMs);
    if (currDist === bestDist) {
      return current.startMs > best.startMs ? current : best;
    }
    return currDist < bestDist ? current : best;
  });
}

export function resolveReportPeriod(
  period: ReportPeriod,
  customStartIso: string,
  customEndIso: string,
  referenceDate: Date = new Date()
): NumericInterval {
  switch (period) {
    case "today": {
      const start = startOfLocalDay(referenceDate).getTime();
      const end = endOfLocalDayExclusive(referenceDate).getTime();
      return { startMs: start, endMs: end };
    }
    case "yesterday": {
      const y = new Date(referenceDate.getFullYear(), referenceDate.getMonth(), referenceDate.getDate() - 1);
      return { startMs: startOfLocalDay(y).getTime(), endMs: endOfLocalDayExclusive(y).getTime() };
    }
    case "week": {
      const dayOfWeek = referenceDate.getDay(); // 0 = domingo
      const start = new Date(referenceDate.getFullYear(), referenceDate.getMonth(), referenceDate.getDate() - dayOfWeek);
      const end = new Date(start.getFullYear(), start.getMonth(), start.getDate() + 7);
      return { startMs: start.getTime(), endMs: end.getTime() };
    }
    case "month": {
      const start = new Date(referenceDate.getFullYear(), referenceDate.getMonth(), 1);
      const end = new Date(referenceDate.getFullYear(), referenceDate.getMonth() + 1, 1);
      return { startMs: start.getTime(), endMs: end.getTime() };
    }
    case "year": {
      const start = new Date(referenceDate.getFullYear(), 0, 1);
      const end = new Date(referenceDate.getFullYear() + 1, 0, 1);
      return { startMs: start.getTime(), endMs: end.getTime() };
    }
    case "custom": {
      const s = new Date(customStartIso);
      const e = new Date(customEndIso);
      const startMs = Number.isNaN(s.getTime()) ? startOfLocalDay(referenceDate).getTime() : startOfLocalDay(s).getTime();
      const endBase = Number.isNaN(e.getTime()) ? referenceDate : e;
      const endMs = Math.max(startMs, endOfLocalDayExclusive(endBase).getTime());
      return { startMs, endMs };
    }
  }
}
