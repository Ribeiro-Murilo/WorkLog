import { describe, expect, it } from "vitest";
import {
  formatClock,
  formatCompactTimer,
  formatCurrencyBRL,
  formatInvoiceNumber,
  parseBrazilianDecimal,
  projectColorHex
} from "../src/shared/format";

describe("format", () => {
  it("formata relógio com e sem segundos", () => {
    expect(formatClock(0, true)).toBe("00:00:00");
    expect(formatClock(0, false)).toBe("00:00");
    expect(formatClock(3665, true)).toBe("01:01:05");
    expect(formatClock(3665, false)).toBe("01:01");
    expect(formatClock(-10, true)).toBe("00:00:00");
  });

  it("formata tempo compacto igual ao Swift", () => {
    expect(formatCompactTimer(45, true)).toBe("00:45");
    expect(formatCompactTimer(45, false)).toBe("00 min");
    expect(formatCompactTimer(2700, false)).toBe("45 min");
    expect(formatCompactTimer(3661, true)).toBe("1:01:01");
    expect(formatCompactTimer(3661, false)).toBe("1:01");
  });

  it("formata moeda BRL e números de fatura", () => {
    expect(formatCurrencyBRL(1250.5)).toContain("1.250,50");
    expect(formatInvoiceNumber(1)).toBe("FAT-0001");
    expect(formatInvoiceNumber(42)).toBe("FAT-0042");
  });

  it("interpreta decimal brasileiro com vírgula ou ponto", () => {
    expect(parseBrazilianDecimal("800,50")).toBeCloseTo(800.5);
    expect(parseBrazilianDecimal("1.200,75")).toBeCloseTo(1200.75);
    expect(parseBrazilianDecimal("500.25")).toBeCloseTo(500.25);
    expect(parseBrazilianDecimal("")).toBe(0);
  });

  it("calcula cor determinística do projeto de forma consistente com o macOS", () => {
    const id = "550E8400-E29B-41D4-A716-446655440000";
    const lower = projectColorHex(id.toLowerCase());
    const upper = projectColorHex(id.toUpperCase());
    expect(lower).toBe(upper);
    expect([
      "#38CCCF",
      "#7A87FF",
      "#FFA14A",
      "#8FD45E",
      "#E385B8",
      "#C7A8F5"
    ]).toContain(upper);
  });
});
