import crypto from "node:crypto";
import type { DatabaseSync } from "node:sqlite";
import { validateCurrencyCode, type CurrencyCode } from "../../src/shared/currency";
import { formatInvoiceNumber } from "../../src/shared/format";
import { intervalsOverlap } from "../../src/shared/periods";
import type { Invoice, InvoiceLineItem, InvoiceStatus } from "../../src/shared/types";
import type { SettingsRepository } from "./settingsRepository";

interface InvoiceRow {
  id: string;
  number: number;
  client: string;
  issue_date: string;
  period_start: string;
  period_end: string;
  line_items_json: string;
  total_value: number;
  currency_code: CurrencyCode;
  status: string;
  notes: string;
  created_at: string;
  updated_at: string;
}

function mapInvoice(row: InvoiceRow): Invoice {
  let lineItems: InvoiceLineItem[] = [];
  try {
    const parsed = JSON.parse(row.line_items_json);
    if (Array.isArray(parsed)) {
      lineItems = parsed.map((item) => ({
        date: String(item.date),
        projectName: String(item.projectName),
        durationSeconds: Number(item.durationSeconds) || 0,
        value: Number(item.value) || 0
      }));
    }
  } catch {
    lineItems = [];
  }
  const totalDurationSeconds = lineItems.reduce((acc, item) => acc + item.durationSeconds, 0);
  return {
    id: row.id,
    number: Number(row.number) || 0,
    formattedNumber: formatInvoiceNumber(Number(row.number) || 0),
    client: row.client,
    issueDate: row.issue_date,
    periodStart: row.period_start,
    periodEnd: row.period_end,
    lineItems,
    totalDurationSeconds,
    totalValue: Number(row.total_value) || 0,
    currencyCode: row.currency_code,
    status: (row.status === "paid" ? "paid" : "pending") as InvoiceStatus,
    notes: row.notes,
    createdAt: row.created_at,
    updatedAt: row.updated_at
  };
}

export class InvoiceRepository {
  constructor(
    private readonly db: DatabaseSync,
    private readonly settingsRepository: SettingsRepository
  ) {}

  fetchAll(): Invoice[] {
    const rows = this.db
      .prepare("SELECT * FROM invoices ORDER BY number DESC")
      .all() as unknown as InvoiceRow[];
    return rows.map(mapInvoice);
  }

  fetchById(id: string): Invoice | null {
    const row = this.db.prepare("SELECT * FROM invoices WHERE id = ?").get(id) as
      | InvoiceRow
      | undefined;
    return row ? mapInvoice(row) : null;
  }

  nextNumber(): number {
    const settings = this.settingsRepository.current();
    const next = settings.lastInvoiceNumber + 1;
    this.settingsRepository.save({ lastInvoiceNumber: next });
    return next;
  }

  hasOverlap(client: string, startMs: number, endMs: number, excludingId?: string | null, currencyCode: CurrencyCode = "BRL"): boolean {
    const rows = this.db
      .prepare("SELECT * FROM invoices WHERE client = ? AND currency_code = ?")
      .all(client, currencyCode) as unknown as InvoiceRow[];
    return rows.some((row) => {
      if (excludingId && row.id === excludingId) return false;
      const pStart = Date.parse(row.period_start);
      const pEnd = Date.parse(row.period_end);
      return intervalsOverlap(pStart, pEnd, startMs, endMs);
    });
  }

  insert(input: {
    id?: string;
    number: number;
    client: string;
    issueDate?: string;
    periodStart: string;
    periodEnd: string;
    lineItems: InvoiceLineItem[];
    currencyCode?: CurrencyCode;
    notes?: string;
    status?: InvoiceStatus;
  }): Invoice {
    const now = new Date().toISOString();
    const totalValue = input.lineItems.reduce((acc, item) => acc + item.value, 0);
    const id = input.id ?? crypto.randomUUID().toUpperCase();
    const issueDate = input.issueDate ?? now;
    const status = input.status ?? "pending";
    const currencyCode = validateCurrencyCode(input.currencyCode === undefined ? "BRL" : input.currencyCode);
    const notes = input.notes ?? "";

    this.db
      .prepare(
        `INSERT INTO invoices (
          id, number, client, issue_date, period_start, period_end,
          line_items_json, total_value, currency_code, status, notes, created_at, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
      )
      .run(
        id,
        input.number,
        input.client,
        issueDate,
        input.periodStart,
        input.periodEnd,
        JSON.stringify(input.lineItems),
        totalValue,
        currencyCode,
        status,
        notes,
        now,
        now
      );

    return this.fetchById(id)!;
  }

  updateStatus(id: string, status: InvoiceStatus): Invoice {
    const now = new Date().toISOString();
    this.db
      .prepare("UPDATE invoices SET status = ?, updated_at = ? WHERE id = ?")
      .run(status, now, id);
    return this.fetchById(id)!;
  }

  upsertRaw(invoice: Invoice): void {
    this.db
      .prepare(
        `INSERT INTO invoices (
          id, number, client, issue_date, period_start, period_end,
          line_items_json, total_value, currency_code, status, notes, created_at, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
          number = excluded.number,
          client = excluded.client,
          issue_date = excluded.issue_date,
          period_start = excluded.period_start,
          period_end = excluded.period_end,
          line_items_json = excluded.line_items_json,
          total_value = excluded.total_value,
          currency_code = excluded.currency_code,
          status = excluded.status,
          notes = excluded.notes,
          created_at = excluded.created_at,
          updated_at = excluded.updated_at`
      )
      .run(
        invoice.id,
        invoice.number,
        invoice.client,
        invoice.issueDate,
        invoice.periodStart,
        invoice.periodEnd,
        JSON.stringify(invoice.lineItems),
        invoice.totalValue,
        invoice.currencyCode,
        invoice.status,
        invoice.notes,
        invoice.createdAt,
        invoice.updatedAt
      );
  }

  delete(id: string): void {
    this.db.prepare("DELETE FROM invoices WHERE id = ?").run(id);
  }

  deleteAll(): void {
    this.db.prepare("DELETE FROM invoices").run();
  }
}
