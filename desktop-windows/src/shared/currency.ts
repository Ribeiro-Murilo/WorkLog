export const CURRENCIES = ["BRL", "USD", "EUR"] as const;
export type CurrencyCode = (typeof CURRENCIES)[number];

export function isCurrencyCode(value: unknown): value is CurrencyCode {
  return value === "BRL" || value === "USD" || value === "EUR";
}

export function validateCurrencyCode(value: unknown): CurrencyCode {
  if (!isCurrencyCode(value)) throw new Error("Moeda inválida.");
  return value;
}

export interface PtaxQuote {
  quoteDate: string;
  checkedDate: string;
  usdRate: number;
  eurRate: number;
}

export interface PtaxState {
  quote: PtaxQuote | null;
  unavailable: boolean;
}

export function convertCurrency(
  value: number,
  source: CurrencyCode,
  target: CurrencyCode,
  quote: PtaxQuote | null
): number | null {
  if (!Number.isFinite(value)) return null;
  if (source === target || value === 0) return value;
  if (!quote) return null;
  const brlRate = { BRL: 1, USD: quote.usdRate, EUR: quote.eurRate };
  const converted = value * (brlRate[source] / brlRate[target]);
  return Number.isFinite(converted) ? converted : null;
}
