import { describe, expect, it } from "vitest";
import { openDatabase } from "../electron/data/database";
import { BillingService } from "../electron/services/billingService";
import { InvoiceRepository } from "../electron/services/invoiceRepository";
import { ProjectRepository } from "../electron/services/projectRepository";
import { ReportPresetRepository } from "../electron/services/reportPresetRepository";
import { ReportService } from "../electron/services/reportService";
import { SessionRepository } from "../electron/services/sessionRepository";
import { SettingsRepository } from "../electron/services/settingsRepository";
import { TimerService } from "../electron/services/timerService";
import { DEFAULT_REPORT_COLUMNS } from "../src/shared/reports";

describe("reportsAndBilling", () => {
  it("gera relatórios detalhados e agrupados e exporta CSV/Excel XML corretos", () => {
    const db = openDatabase(":memory:");
    const projects = new ProjectRepository(db);
    const sessions = new SessionRepository(db);
    const settings = new SettingsRepository(db);
    const presets = new ReportPresetRepository(db);
    const timer = new TimerService(sessions, projects);
    const reportService = new ReportService(projects, sessions, settings);

    const p = projects.insert({
      name: "API, Vendas",
      client: "Empresa \"X\"",
      dailyRate: 800,
      category: "work",
      tags: ["node", "ts"],
      descriptionText: "Serviço <principal>",
      status: "active"
    });

    const ref = new Date(2026, 9, 15, 12, 0, 0);
    timer.addManualSession({
      projectId: p.id,
      startTime: new Date(2026, 9, 15, 9, 0, 0).toISOString(),
      endTime: new Date(2026, 9, 15, 11, 0, 0).toISOString(),
      note: "Entrega 1"
    });
    timer.addManualSession({
      projectId: p.id,
      startTime: new Date(2026, 9, 15, 14, 0, 0).toISOString(),
      endTime: new Date(2026, 9, 15, 16, 0, 0).toISOString(),
      note: "Entrega 2"
    });

    const grouped = reportService.generate(
      {
        period: "today",
        customStart: "",
        customEnd: "",
        projectId: null,
        client: null,
        category: null,
        status: null,
        tag: "ts",
        selectedColumns: DEFAULT_REPORT_COLUMNS,
        grouping: "byProjectAndDay"
      },
      ref
    );

    expect(grouped.rows).toHaveLength(1);
    expect(grouped.rows[0].sessionCount).toBe(2);
    expect(grouped.rows[0].durationSeconds).toBe(14400);
    expect(grouped.rows[0].estimatedValue).toBeCloseTo(400);
    expect(grouped.rows[0].note).toBe("Entrega 2 | Entrega 1");

    const payloads = reportService.buildExportPayloads(
      {
        period: "today",
        customStart: "",
        customEnd: "",
        projectId: null,
        client: null,
        category: null,
        status: null,
        tag: null,
        selectedColumns: ["project", "client", "description"],
        grouping: "byProjectAndDay"
      },
      null,
      ref
    );
    expect(payloads.csv.startsWith("\uFEFF")).toBe(true);
    expect(payloads.csv).toContain("\"API, Vendas\"");
    expect(payloads.csv).toContain("\"Empresa \"\"X\"\"\"");
    expect(payloads.excelXml).toContain("&lt;principal&gt;");

    presets.upsertByName("Mensal", ["project", "duration", "value"], "byProjectAndDay");
    expect(presets.fetchAll()).toHaveLength(1);

    timer.dispose();
    db.close();
  });

  it("emite faturas com numeração monotônica e bloqueia períodos sobrepostos", () => {
    const db = openDatabase(":memory:");
    const projects = new ProjectRepository(db);
    const sessions = new SessionRepository(db);
    const settings = new SettingsRepository(db);
    const invoices = new InvoiceRepository(db, settings);
    const timer = new TimerService(sessions, projects);
    const billing = new BillingService(projects, sessions, invoices, settings);

    const p = projects.insert({
      name: "Consultoria",
      client: "ACME",
      dailyRate: 800,
      category: "work",
      tags: [],
      descriptionText: "",
      status: "active"
    });

    const ref = new Date(2026, 9, 15, 12, 0, 0);
    timer.addManualSession({
      projectId: p.id,
      startTime: new Date(2026, 9, 15, 9, 0, 0).toISOString(),
      endTime: new Date(2026, 9, 15, 13, 0, 0).toISOString(),
      note: ""
    });

    const inv1 = billing.generateInvoice({
      client: "ACME",
      period: "month",
      customStart: "",
      customEnd: "",
      notes: "Pagamento PIX",
      referenceDate: ref
    });
    expect(inv1.formattedNumber).toBe("FAT-0001");
    expect(inv1.totalValue).toBeCloseTo(400);

    // Período sobreposto falha
    expect(() =>
      billing.generateInvoice({
        client: "ACME",
        period: "month",
        customStart: "",
        customEnd: "",
        notes: "",
        referenceDate: ref
      })
    ).toThrow("sobreposto");

    // Excluir fatura não reaproveita número anterior
    billing.deleteInvoice(inv1.id);
    const inv2 = billing.generateInvoice({
      client: "ACME",
      period: "month",
      customStart: "",
      customEnd: "",
      notes: "",
      referenceDate: ref
    });
    expect(inv2.formattedNumber).toBe("FAT-0002");

    const paid = billing.toggleStatus(inv2.id);
    expect(paid.status).toBe("paid");

    timer.dispose();
    db.close();
  });
});
