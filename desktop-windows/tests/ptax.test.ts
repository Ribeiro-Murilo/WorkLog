import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { expect, it, vi } from "vitest";
import { fetchPtaxQuote, PtaxService } from "../electron/services/ptaxService";
import { convertCurrency } from "../src/shared/currency";

function bulletin(day: string, rate: number, kind = "Fechamento") {
  return { dataHoraCotacao: `${day} 13:00:00.000`, cotacaoVenda: rate, tipoBoletim: kind };
}

it("seleciona o fechamento válido mais recente em comum e usa as duas taxas para a conversão cruzada", async () => {
  const now = new Date("2026-11-20T02:00:00.000Z");
  const fetchResponse: typeof fetch = vi.fn(async (input) => {
    const url = new URL(String(input));
    expect(url.pathname).toContain("CotacaoMoedaPeriodo");
    expect(url.searchParams.get("@dataFinalCotacao")).toBe("'11-19-2026'");
    const usd = url.searchParams.get("@moeda") === "'USD'";
    return Response.json({ value: usd
      ? [bulletin("2026-11-19", 5.7), bulletin("2026-11-18", 5, "Fechamento PTAX"), bulletin("2026-11-17", 4)]
      : [bulletin("2026-11-19", 0), bulletin("2026-11-19", 8, "Intermediário"), bulletin("2026-11-18", 6.25), bulletin("2026-11-17", 6)]
    });
  });
  const quote = await fetchPtaxQuote(now, fetchResponse);
  expect(quote).toEqual({ quoteDate: "2026-11-18", checkedDate: "2026-11-19", usdRate: 5, eurRate: 6.25 });
  expect(convertCurrency(100, "USD", "EUR", quote)).toBe(80);
  expect(convertCurrency(0, "USD", "BRL", null)).toBe(0);
  expect(convertCurrency(100, "USD", "USD", null)).toBe(100);
  expect(convertCurrency(100, "USD", "BRL", null)).toBeNull();
  expect(convertCurrency(Number.MAX_VALUE, "USD", "BRL", quote)).toBeNull();
});

it("compartilha consulta por dia, conserva a cotação em erro e aguarda antes de tentar novamente", async () => {
  const dir = mkdtempSync(join(tmpdir(), "worklog-ptax-"));
  try {
    const file = join(dir, "ptax.json");
    const quote = { quoteDate: "2026-11-18", checkedDate: "2026-11-19", usdRate: 5, eurRate: 6.25 };
    const fetchQuote = vi.fn()
      .mockResolvedValueOnce(quote)
      .mockRejectedValueOnce(new Error("offline"))
      .mockResolvedValueOnce({ ...quote, checkedDate: "2026-11-20" });
    const service = new PtaxService(file, () => {}, fetchQuote);
    const beforeMidnight = new Date("2026-11-20T02:59:00.000Z");
    await Promise.all([service.refresh(beforeMidnight), service.refresh(beforeMidnight)]);
    expect(service.state).toEqual({ quote, unavailable: false });
    expect(fetchQuote).toHaveBeenCalledTimes(1);

    const reopened = new PtaxService(file, () => {}, fetchQuote);
    await reopened.refresh(beforeMidnight);
    expect(reopened.state.quote).toEqual(quote);
    await reopened.refresh(new Date("2026-11-20T03:00:00.000Z"));
    expect(reopened.state).toEqual({ quote, unavailable: true });
    await reopened.refresh(new Date("2026-11-20T03:01:00.000Z"));
    expect(fetchQuote).toHaveBeenCalledTimes(2);
    await reopened.refresh(new Date("2026-11-20T03:30:00.000Z"));
    expect(reopened.state).toEqual({ quote: { ...quote, checkedDate: "2026-11-20" }, unavailable: false });
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

it("mantém a cotação recente se o serviço retornar um fechamento mais antigo", async () => {
  const dir = mkdtempSync(join(tmpdir(), "worklog-ptax-"));
  try {
    const quote = { quoteDate: "2026-11-18", checkedDate: "2026-11-19", usdRate: 5, eurRate: 6.25 };
    const fetchQuote = vi.fn()
      .mockResolvedValueOnce(quote)
      .mockResolvedValueOnce({ ...quote, quoteDate: "2026-11-17", checkedDate: "2026-11-20" });
    const service = new PtaxService(join(dir, "ptax.json"), () => {}, fetchQuote);
    await service.refresh(new Date("2026-11-19T12:00:00.000Z"));
    await service.refresh(new Date("2026-11-20T12:00:00.000Z"));
    expect(service.state).toEqual({ quote, unavailable: true });
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});
