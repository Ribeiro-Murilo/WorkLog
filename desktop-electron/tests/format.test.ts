import { describe, expect, it } from "vitest";

import { formatDuration, secondsBetween } from "../src/shared/format";

describe("formatDuration", () => {
  it("formats elapsed seconds as HH:MM:SS by default", () => {
    expect(formatDuration(0)).toBe("00:00:00");
    expect(formatDuration(65)).toBe("00:01:05");
    expect(formatDuration(3661)).toBe("01:01:01");
  });

  it("omits seconds when requested", () => {
    expect(formatDuration(3661, false)).toBe("01:01");
  });

  it("floors fractional seconds", () => {
    expect(formatDuration(90.9)).toBe("00:01:30");
  });

  it("clamps negative durations to zero", () => {
    expect(formatDuration(-5)).toBe("00:00:00");
  });
});

describe("secondsBetween", () => {
  it("returns the elapsed whole seconds between two timestamps", () => {
    expect(secondsBetween("2026-01-01T09:00:00.000Z", "2026-01-01T10:01:30.000Z")).toBe(3690);
  });

  it("floors fractional second differences", () => {
    expect(secondsBetween("2026-01-01T09:00:00.000Z", "2026-01-01T09:00:01.999Z")).toBe(1);
  });

  it("clamps inverted ranges to zero", () => {
    expect(secondsBetween("2026-01-01T10:00:00.000Z", "2026-01-01T09:00:00.000Z")).toBe(0);
  });
});
