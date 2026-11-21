import { CURRENCIES, type CurrencyCode } from "./currency";
import type { TimeFormatPreference } from "./types";

const PROJECT_PALETTE = [
  "#38CCCF", // rgb(0.22, 0.80, 0.81)
  "#7A87FF", // rgb(0.48, 0.53, 1.00)
  "#FFA14A", // rgb(1.00, 0.63, 0.29)
  "#8FD45E", // rgb(0.56, 0.83, 0.37)
  "#E385B8", // rgb(0.89, 0.52, 0.72)
  "#C7A8F5"  // rgb(0.78, 0.66, 0.96)
] as const;

/** Formata como "HH:MM:SS" ou "HH:MM" dependendo de `showSeconds`. */
export function formatClock(seconds: number, showSeconds: boolean): string {
  const totalSeconds = Math.max(0, Math.floor(seconds));
  const hours = Math.floor(totalSeconds / 3600);
  const minutes = Math.floor((totalSeconds % 3600) / 60);
  const secs = totalSeconds % 60;
  const hh = String(hours).padStart(2, "0");
  const mm = String(minutes).padStart(2, "0");
  const ss = String(secs).padStart(2, "0");
  return showSeconds ? `${hh}:${mm}:${ss}` : `${hh}:${mm}`;
}

/** Formato compacto para o badge do notch e tray: espelha `compactMenuBarString` do Swift. */
export function formatCompactTimer(seconds: number, showSeconds: boolean): string {
  const totalSeconds = Math.max(0, Math.floor(seconds));
  const hours = Math.floor(totalSeconds / 3600);
  const minutes = Math.floor((totalSeconds % 3600) / 60);
  const secs = totalSeconds % 60;
  const mm = String(minutes).padStart(2, "0");
  const ss = String(secs).padStart(2, "0");

  if (hours > 0) {
    return showSeconds ? `${hours}:${mm}:${ss}` : `${hours}:${mm}`;
  }
  return showSeconds ? `${mm}:${ss}` : `${mm} min`;
}

const currencyFormatters = new Map(CURRENCIES.map((currency) => [currency,
  new Intl.NumberFormat("pt-BR", { style: "currency", currency })
]));
const amountFormatter = new Intl.NumberFormat("pt-BR", {
  minimumFractionDigits: 2, maximumFractionDigits: 2
});

export function formatCurrency(value: number, currency: CurrencyCode, useCode = false): string {
  const safe = Number.isFinite(value) ? value : 0;
  if (useCode) return `${currency} ${amountFormatter.format(safe)}`;
  return currencyFormatters.get(currency)!.format(safe);
}

export function formatCurrencyTotals(totals: Partial<Record<CurrencyCode, number>>): string {
  return CURRENCIES.flatMap((currency) => {
    const value = totals[currency];
    return value === undefined ? [] : [formatCurrency(value, currency, true)];
  }).join("  ·  ") || "—";
}

export function formatShortDate(iso: string): string {
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return "—";
  return new Intl.DateTimeFormat("pt-BR", {
    day: "2-digit",
    month: "2-digit",
    year: "numeric"
  }).format(d);
}

export function formatShortTime(iso: string, timeFormat: TimeFormatPreference = "twentyFourHour"): string {
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return "—";
  return new Intl.DateTimeFormat("pt-BR", {
    hour: "2-digit",
    minute: "2-digit",
    hour12: timeFormat === "twelveHour"
  }).format(d);
}

export function formatDateTimeSeconds(iso: string): string {
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return "—";
  const day = String(d.getDate()).padStart(2, "0");
  const month = String(d.getMonth() + 1).padStart(2, "0");
  const year = d.getFullYear();
  const hh = String(d.getHours()).padStart(2, "0");
  const mm = String(d.getMinutes()).padStart(2, "0");
  const ss = String(d.getSeconds()).padStart(2, "0");
  return `${day}/${month}/${year} ${hh}:${mm}:${ss}`;
}

export function formatDateTimeShort(iso: string, timeFormat: TimeFormatPreference = "twentyFourHour"): string {
  return `${formatShortDate(iso)} ${formatShortTime(iso, timeFormat)}`;
}

/**
 * Mesma função de hash de `NotchPanelStyle.projectColor` em Swift:
 * percorre bytes UTF-8 de `id.uuidString` (uppercase) com fator 31 mod 6.
 */
export function projectColorHex(id: string): string {
  const normalized = id.toUpperCase();
  const bytes = new TextEncoder().encode(normalized);
  let index = 0;
  for (const byte of bytes) {
    index = (index * 31 + byte) % PROJECT_PALETTE.length;
  }
  return PROJECT_PALETTE[index];
}

export function parseBrazilianDecimal(input: string): number {
  const trimmed = input.trim();
  if (!trimmed) return 0;
  // Se contém vírgula e ponto (ex: 1.234,56), remove separador de milhar antes.
  const normalized =
    trimmed.includes(",") && trimmed.includes(".")
      ? trimmed.replace(/\./g, "").replace(",", ".")
      : trimmed.replace(",", ".");
  const parsed = Number(normalized);
  return Number.isFinite(parsed) ? parsed : Number.NaN;
}

export function formatInvoiceNumber(num: number): string {
  return `FAT-${String(Math.max(0, Math.floor(num))).padStart(4, "0")}`;
}
