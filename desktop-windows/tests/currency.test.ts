import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { expect, it } from "vitest";
import { openDatabase } from "../electron/data/database";
import { BillingService } from "../electron/services/billingService";
import { InvoiceRepository } from "../electron/services/invoiceRepository";
import { ProjectRepository } from "../electron/services/projectRepository";
import { ReportService } from "../electron/services/reportService";
import { SessionRepository } from "../electron/services/sessionRepository";
import { SettingsRepository } from "../electron/services/settingsRepository";
import { TimerService } from "../electron/services/timerService";

const project = { name: "Projeto", client: "Cliente", dailyRate: 800, category: "work", tags: [], descriptionText: "", status: "active" } as const;

function setup() {
  const db = openDatabase(":memory:");
  const projects = new ProjectRepository(db);
  const sessions = new SessionRepository(db);
  const settings = new SettingsRepository(db);
  const invoices = new InvoiceRepository(db, settings);
  const timer = new TimerService(sessions, projects);
  return { projects, sessions, timer, reports: new ReportService(projects, sessions, settings),
    billing: new BillingService(projects, sessions, invoices, settings), close: () => { timer.dispose(); db.close(); } };
}

it("bloqueia a moeda de um projeto assim que existe sessão aberta e permite editar a diária", () => {
  const services = setup();
  try {
    const data = { ...project, tags: [], currencyCode: "USD" as const };
    const saved = services.projects.insert(data);
    expect(saved.currencyCode).toBe("USD");
    const session = services.timer.start(saved.id);
    expect(() => services.projects.update(saved.id, { ...data, currencyCode: "EUR" })).toThrow(/moeda/i);
    expect(services.projects.update(saved.id, { ...data, dailyRate: 900 }).dailyRate).toBe(900);
    services.timer.stop();
    services.sessions.delete(session.id);
    expect(services.projects.update(saved.id, { ...data, currencyCode: "EUR" }).currencyCode).toBe("EUR");
  } finally {
    services.close();
  }
});

it("totaliza a moeda de cada projeto e permite faturas sobrepostas em moedas distintas", () => {
  const services = setup();
  try {
    const usd = services.projects.insert({ ...project, tags: [], currencyCode: "USD" });
    const eur = services.projects.insert({ ...project, name: "Outro", tags: [], currencyCode: "EUR", dailyRate: 400 });
    services.timer.addManualSession({ projectId: usd.id, startTime: new Date(2026, 10, 10, 9).toISOString(), endTime: new Date(2026, 10, 10, 11).toISOString(), note: "" });
    services.timer.addManualSession({ projectId: eur.id, startTime: new Date(2026, 10, 10, 13).toISOString(), endTime: new Date(2026, 10, 10, 15).toISOString(), note: "" });
    const common = { period: "today", customStart: "", customEnd: "" } as const;
    const referenceDate = new Date(2026, 10, 10, 18);
    const filter = { ...common, projectId: null, client: null, category: null, status: null, tag: null,
      selectedColumns: ["value"], grouping: "byProjectAndDay" } as const;
    const selectedFilter = { ...filter, selectedColumns: [...filter.selectedColumns] };
    const report = services.reports.generate(selectedFilter, referenceDate);
    expect(report.totalsByCurrency).toEqual({ USD: 200, EUR: 100 });
    const { csv, excelXml, pdfHtml } = services.reports.buildExportPayloads(selectedFilter, null, referenceDate);
    for (const output of [csv, excelXml, pdfHtml]) {
      expect(output).toContain("USD 200,00");
      expect(output).toContain("EUR 100,00");
    }
    for (const output of [csv, excelXml]) {
      expect(output).toContain("Subtotal USD 200,00");
      expect(output).toContain("Subtotal EUR 100,00");
    }
    const withoutValue = services.reports.buildExportPayloads(
      { ...selectedFilter, selectedColumns: ["project"] }, null, referenceDate
    );
    expect(withoutValue.csv).not.toContain("Subtotal");
    expect(withoutValue.pdfHtml).not.toContain("USD 200,00");
    const params = { ...common, referenceDate, client: "Cliente", notes: "" };
    expect(services.billing.generateInvoice({ ...params, currencyCode: "USD" })).toMatchObject({ currencyCode: "USD", totalValue: 200 });
    expect(services.billing.generateInvoice({ ...params, currencyCode: "EUR" })).toMatchObject({ currencyCode: "EUR", totalValue: 100 });
    expect(() => services.billing.generateInvoice({ ...params, currencyCode: "EUR" })).toThrow(/sobreposto/);
  } finally {
    services.close();
  }
});

it("migra projetos e faturas do SQLite antigo para BRL e preserva a moeda em futuras aberturas", () => {
  const directory = mkdtempSync(join(tmpdir(), "worklog-currency-"));
  try {
    const path = join(directory, "worklog.sqlite");
    const previous = openDatabase(path);
    const previousProject = new ProjectRepository(previous).insert({ ...project, tags: [] });
    const previousInvoice = new InvoiceRepository(previous, new SettingsRepository(previous)).insert({
      number: 1, client: previousProject.client, periodStart: "2026-11-01", periodEnd: "2026-11-02", lineItems: []
    });
    previous.exec("DROP INDEX idx_invoices_client_currency");
    previous.exec("ALTER TABLE invoices DROP COLUMN currency_code");
    previous.exec("ALTER TABLE projects DROP COLUMN currency_code");
    previous.close();

    const migrated = openDatabase(path);
    const projects = new ProjectRepository(migrated);
    expect(projects.fetchById(previousProject.id)).toMatchObject({ currencyCode: "BRL", dailyRate: 800 });
    expect(new InvoiceRepository(migrated, new SettingsRepository(migrated)).fetchById(previousInvoice.id))
      .toMatchObject({ currencyCode: "BRL", totalValue: 0 });
    projects.update(previousProject.id, { ...project, tags: [], currencyCode: "USD" });
    migrated.close();

    const reopened = openDatabase(path);
    expect(new ProjectRepository(reopened).fetchById(previousProject.id)?.currencyCode).toBe("USD");
    reopened.close();
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
});
