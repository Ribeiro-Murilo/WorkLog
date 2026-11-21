import { formatClock, formatCurrency, formatShortDate } from "../../src/shared/format";
import { validateCurrencyCode, type CurrencyCode } from "../../src/shared/currency";
import { resolveReportPeriod } from "../../src/shared/periods";
import { buildDetailedReportRows, buildInvoicePdfHtml } from "../../src/shared/reports";
import type {
  BillingPreview,
  Invoice,
  InvoiceLineItem,
  ReportPeriod,
  ReportRow
} from "../../src/shared/types";
import type { InvoiceRepository } from "./invoiceRepository";
import type { ProjectRepository } from "./projectRepository";
import type { SessionRepository } from "./sessionRepository";
import type { SettingsRepository } from "./settingsRepository";

export class BillingService {
  constructor(
    private readonly projectRepository: ProjectRepository,
    private readonly sessionRepository: SessionRepository,
    private readonly invoiceRepository: InvoiceRepository,
    private readonly settingsRepository: SettingsRepository
  ) {}

  availableClients(): string[] {
    const projects = this.projectRepository.fetchAll(true);
    return Array.from(new Set(projects.map((p) => p.client))).sort((a, b) =>
      a.localeCompare(b, "pt-BR")
    );
  }

  preview(params: {
    client: string | null;
    period: ReportPeriod;
    currencyCode?: CurrencyCode;
    customStart: string;
    customEnd: string;
    referenceDate?: Date;
  }): BillingPreview {
    const currencyCode = validateCurrencyCode(params.currencyCode === undefined ? "BRL" : params.currencyCode);
    const interval = resolveReportPeriod(
      params.period,
      params.customStart,
      params.customEnd,
      params.referenceDate ?? new Date()
    );
    const periodStart = new Date(interval.startMs).toISOString();
    const periodEnd = new Date(interval.endMs).toISOString();

    if (!params.client) {
      return {
        client: null,
        periodStart,
        periodEnd,
        lineItems: [],
        totalDurationSeconds: 0,
        totalValue: 0,
        currencyCode,
        overlapsExistingInvoice: false
      };
    }

    const projects = this.projectRepository.fetchAll(true);
    const projectsById = new Map(projects.map((p) => [p.id, p]));
    const sessions = this.sessionRepository
      .fetchSessionsInInterval(interval.startMs, interval.endMs)
      .filter((session) => {
        const project = session.projectId ? projectsById.get(session.projectId) : undefined;
        return project?.client === params.client && project.currencyCode === currencyCode;
      });

    const detailed = buildDetailedReportRows(
      sessions,
      projectsById,
      interval.startMs,
      interval.endMs
    );

    const order: string[] = [];
    const buckets = new Map<string, ReportRow[]>();
    const projectIdBySessionId = new Map(sessions.map((s) => [s.id, s.projectId ?? "—"]));

    for (const row of detailed) {
      const sid = row.id.split("#")[0];
      const pid = projectIdBySessionId.get(sid) ?? "—";
      const key = `${pid}#${Date.parse(row.date)}`;
      if (!buckets.has(key)) {
        buckets.set(key, []);
        order.push(key);
      }
      buckets.get(key)!.push(row);
    }

    const lineItems: InvoiceLineItem[] = order
      .map((key) => {
        const group = buckets.get(key)!;
        const first = group[0];
        return {
          date: first.date,
          projectName: first.projectName,
          durationSeconds: group.reduce((acc, r) => acc + r.durationSeconds, 0),
          value: group.reduce((acc, r) => acc + r.estimatedValue, 0)
        };
      })
      .sort((a, b) => Date.parse(a.date) - Date.parse(b.date));

    const overlapsExistingInvoice = this.invoiceRepository.hasOverlap(
      params.client,
      interval.startMs,
      interval.endMs,
      null,
      currencyCode
    );

    return {
      client: params.client,
      periodStart,
      periodEnd,
      lineItems,
      totalDurationSeconds: lineItems.reduce((acc, i) => acc + i.durationSeconds, 0),
      totalValue: lineItems.reduce((acc, i) => acc + i.value, 0),
      currencyCode,
      overlapsExistingInvoice
    };
  }

  generateInvoice(params: {
    client: string;
    period: ReportPeriod;
    currencyCode?: CurrencyCode;
    customStart: string;
    customEnd: string;
    notes: string;
    referenceDate?: Date;
  }): Invoice {
    const preview = this.preview(params);
    if (preview.lineItems.length === 0) {
      throw new Error("Nenhuma sessão encerrada no período selecionado.");
    }
    if (preview.overlapsExistingInvoice) {
      throw new Error(`Já existe uma fatura para ${params.client} com período sobreposto a este.`);
    }
    const number = this.invoiceRepository.nextNumber();
    return this.invoiceRepository.insert({
      number,
      client: params.client,
      periodStart: preview.periodStart,
      periodEnd: preview.periodEnd,
      lineItems: preview.lineItems,
      currencyCode: preview.currencyCode,
      notes: params.notes
    });
  }

  toggleStatus(invoiceId: string): Invoice {
    const invoice = this.invoiceRepository.fetchById(invoiceId);
    if (!invoice) throw new Error("Fatura não encontrada.");
    const nextStatus = invoice.status === "pending" ? "paid" : "pending";
    return this.invoiceRepository.updateStatus(invoice.id, nextStatus);
  }

  deleteInvoice(invoiceId: string): void {
    this.invoiceRepository.delete(invoiceId);
  }

  buildInvoicePdfHtml(invoiceId: string, logoDataUrl: string | null = null): string {
    const invoice = this.invoiceRepository.fetchById(invoiceId);
    if (!invoice) throw new Error("Fatura não encontrada.");
    const settings = this.settingsRepository.current();
    return buildInvoicePdfHtml({
      issuerName: settings.invoiceIssuerName,
      issuerDetails: settings.invoiceIssuerDetails,
      invoiceNumber: invoice.formattedNumber,
      issueDateText: formatShortDate(invoice.issueDate),
      periodStartText: formatShortDate(invoice.periodStart),
      periodEndText: formatShortDate(invoice.periodEnd),
      client: invoice.client,
      lineItems: invoice.lineItems,
      totalDurationText: formatClock(invoice.totalDurationSeconds, false),
      totalValueText: formatCurrency(invoice.totalValue, invoice.currencyCode, true),
      currencyCode: invoice.currencyCode,
      notes: invoice.notes,
      logoDataUrl: settings.includeLogoInPDF ? logoDataUrl : null
    });
  }
}
