import { readFileSync, renameSync, writeFileSync } from "node:fs";
import type { PtaxQuote, PtaxState } from "../../src/shared/currency";

const dayFormatter = new Intl.DateTimeFormat("sv-SE", { timeZone: "America/Sao_Paulo", dateStyle: "short" });
const endpoint = "https://olinda.bcb.gov.br/olinda/servico/PTAX/versao/v1/odata/"
  + "CotacaoMoedaPeriodo(moeda=@moeda,dataInicial=@dataInicial,dataFinalCotacao=@dataFinalCotacao)";
const retryInterval = 15 * 60 * 1000;
const dayMs = 24 * 60 * 60 * 1000;
const isoDayPattern = /^\d{4}-\d{2}-\d{2}$/;

function dateInSaoPaulo(date: Date): string {
  return dayFormatter.format(date);
}

function isIsoDay(value: unknown): value is string {
  if (typeof value !== "string" || !isoDayPattern.test(value)) return false;
  const date = new Date(value);
  return Number.isFinite(date.getTime()) && date.toISOString().slice(0, 10) === value;
}

function formatOlindaDate(date: string): string {
  const [year, month, day] = date.split("-");
  return `'${month}-${day}-${year}'`;
}

function isPositiveRate(value: unknown): value is number {
  return typeof value === "number" && Number.isFinite(value) && value > 0;
}

async function closingRates(
  currency: "USD" | "EUR", firstDay: string, lastDay: string, fetchResponse: typeof fetch
): Promise<Map<string, number>> {
  const url = new URL(endpoint);
  url.searchParams.set("@moeda", `'${currency}'`);
  url.searchParams.set("@dataInicial", formatOlindaDate(firstDay));
  url.searchParams.set("@dataFinalCotacao", formatOlindaDate(lastDay));
  url.searchParams.set("$format", "json");
  const response = await fetchResponse(url, { signal: AbortSignal.timeout(10_000) });
  if (!response.ok) throw new Error(`PTAX respondeu HTTP ${response.status}.`);
  const data = await response.json() as { value?: unknown } | null;
  if (!Array.isArray(data?.value)) throw new Error("Resposta PTAX inválida.");

  const closing = new Map<string, { timestamp: string; rate: number }>();
  for (const row of data.value) {
    if (row?.tipoBoletim !== "Fechamento" && row?.tipoBoletim !== "Fechamento PTAX") continue;
    if (typeof row.dataHoraCotacao !== "string" || !isPositiveRate(row.cotacaoVenda)) continue;
    const day = row.dataHoraCotacao.slice(0, 10);
    if (!isIsoDay(day) || day < firstDay || day > lastDay) continue;
    const previous = closing.get(day);
    if (!previous || row.dataHoraCotacao > previous.timestamp) {
      closing.set(day, { timestamp: row.dataHoraCotacao, rate: row.cotacaoVenda });
    }
  }
  return new Map(Array.from(closing, ([day, value]) => [day, value.rate]));
}

export async function fetchPtaxQuote(now: Date, fetchResponse: typeof fetch = fetch): Promise<PtaxQuote> {
  const checkedDate = dateInSaoPaulo(now);
  const firstDay = new Date(Date.parse(checkedDate) - 10 * dayMs).toISOString().slice(0, 10);
  const [usd, eur] = await Promise.all([
    closingRates("USD", firstDay, checkedDate, fetchResponse),
    closingRates("EUR", firstDay, checkedDate, fetchResponse)
  ]);
  const quoteDate = [...usd.keys()].filter((day) => eur.has(day)).sort().at(-1);
  if (!quoteDate) throw new Error("A PTAX ainda não tem fechamento comum para USD e EUR.");
  return { quoteDate, checkedDate, usdRate: usd.get(quoteDate)!, eurRate: eur.get(quoteDate)! };
}

function readQuote(path: string): PtaxQuote | null {
  try {
    const quote = JSON.parse(readFileSync(path, "utf8")) as Partial<PtaxQuote> | null;
    if (!isIsoDay(quote?.quoteDate) || !isIsoDay(quote?.checkedDate)
      || quote.quoteDate > quote.checkedDate
      || !isPositiveRate(quote.usdRate) || !isPositiveRate(quote.eurRate)) return null;
    return quote as PtaxQuote;
  } catch {
    return null;
  }
}

function nextDayStart(now: Date): number {
  const currentDay = dateInSaoPaulo(now);
  let lower = now.getTime();
  let upper = lower + 26 * 60 * 60 * 1000;
  while (upper - lower > 1) {
    const mid = Math.floor((lower + upper) / 2);
    if (dateInSaoPaulo(new Date(mid)) === currentDay) lower = mid;
    else upper = mid;
  }
  return upper;
}

export class PtaxService {
  private quote: PtaxQuote | null;
  private failedDay: string | null = null;
  private retryAfter = 0;
  private pending: Promise<void> | null = null;
  private wakeTimer: NodeJS.Timeout | null = null;
  private running = false;
  private disposed = false;

  constructor(
    private readonly path: string,
    private readonly onChange: () => void,
    private readonly fetchQuote: (now: Date) => Promise<PtaxQuote> = fetchPtaxQuote
  ) {
    this.quote = readQuote(path);
  }

  get state(): PtaxState {
    return { quote: this.quote, unavailable: this.failedDay !== null };
  }

  start(): void {
    this.running = true;
    this.wake();
  }

  stop(): void {
    this.running = false;
    this.disposed = true;
    if (this.wakeTimer) clearTimeout(this.wakeTimer);
  }

  wake = (): void => {
    if (!this.running) return;
    void this.refresh().finally(() => this.schedule());
  };

  refresh(now: Date = new Date()): Promise<void> {
    if (this.pending) return this.pending;
    const day = dateInSaoPaulo(now);
    if (this.disposed || this.quote?.checkedDate === day
      || (this.failedDay === day && now.getTime() < this.retryAfter)) return Promise.resolve();

    this.pending = this.updateQuote(now, day).finally(() => { this.pending = null; });
    return this.pending;
  }

  private async updateQuote(now: Date, day: string): Promise<void> {
    const wasUnavailable = this.failedDay !== null;
    let updated = false;
    try {
      const quote = await this.fetchQuote(now);
      if (this.disposed) return;
      const cachedDay = this.quote?.quoteDate;
      if (quote.checkedDate !== day || !isIsoDay(quote.quoteDate) || quote.quoteDate > day
        || !isPositiveRate(quote.usdRate) || !isPositiveRate(quote.eurRate)
        || (cachedDay && cachedDay <= day && quote.quoteDate < cachedDay)) {
        throw new Error("A PTAX retornou um fechamento inválido ou anterior ao que está salvo.");
      }
      writeFileSync(`${this.path}.tmp`, JSON.stringify(quote));
      renameSync(`${this.path}.tmp`, this.path);
      this.quote = quote;
      this.failedDay = null;
      updated = true;
    } catch {
      if (this.disposed) return;
      this.failedDay = day;
      this.retryAfter = now.getTime() + retryInterval;
    }
    if (updated || wasUnavailable !== (this.failedDay !== null)) this.onChange();
  }

  private schedule(): void {
    if (!this.running) return;
    if (this.wakeTimer) clearTimeout(this.wakeTimer);
    const now = new Date();
    const day = dateInSaoPaulo(now);
    const nextRefresh = this.quote?.checkedDate === day
      ? nextDayStart(now)
      : this.failedDay === day
        ? Math.min(this.retryAfter, nextDayStart(now))
        : now.getTime();
    this.wakeTimer = setTimeout(this.wake, Math.max(1, nextRefresh - now.getTime()));
  }
}
