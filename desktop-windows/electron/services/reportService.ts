import { formatClock, formatCurrencyBRL, formatShortDate, formatShortTime } from "../../src/shared/format";
import { resolveReportPeriod } from "../../src/shared/periods";
import {
  DEFAULT_REPORT_COLUMNS,
  REPORT_COLUMN_META,
  buildCsvContent,
  buildExcelXmlContent,
  buildReportPdfHtml,
  buildReportRows,
  formatReportColumnValue
} from "../../src/shared/reports";
import {
  REPORT_PERIOD_LABELS,
  type ReportColumn,
  type ReportFilter,
  type ReportResult
} from "../../src/shared/types";
import type { ProjectRepository } from "./projectRepository";
import type { SessionRepository } from "./sessionRepository";
import type { SettingsRepository } from "./settingsRepository";

export class ReportService {
  constructor(
    private readonly projectRepository: ProjectRepository,
    private readonly sessionRepository: SessionRepository,
    private readonly settingsRepository: SettingsRepository
  ) {}

  generate(filter: ReportFilter, referenceDate: Date = new Date()): ReportResult {
    const interval = resolveReportPeriod(
      filter.period,
      filter.customStart,
      filter.customEnd,
      referenceDate
    );
    const allProjects = this.projectRepository.fetchAll(true);
    const projectsById = new Map(allProjects.map((p) => [p.id, p]));

    let sessions = this.sessionRepository.fetchSessionsInInterval(interval.startMs, interval.endMs);

    if (filter.projectId) {
      sessions = sessions.filter((s) => s.projectId === filter.projectId);
    }
    if (filter.client && filter.client.trim() !== "") {
      const needle = filter.client.trim().toLocaleLowerCase("pt-BR");
      sessions = sessions.filter((s) => {
        const client = s.projectId ? projectsById.get(s.projectId)?.client ?? "" : "";
        return client.toLocaleLowerCase("pt-BR").includes(needle);
      });
    }
    if (filter.category) {
      sessions = sessions.filter((s) => s.category === filter.category);
    }
    if (filter.status) {
      sessions = sessions.filter((s) => s.status === filter.status);
    }
    if (filter.tag && filter.tag.trim() !== "") {
      const needle = filter.tag.trim().toLocaleLowerCase("pt-BR");
      sessions = sessions.filter((s) => {
        const tags = s.projectId ? projectsById.get(s.projectId)?.tags ?? [] : [];
        return tags.some((tag) => tag.toLocaleLowerCase("pt-BR").includes(needle));
      });
    }

    const { rows, detailedRows } = buildReportRows(
      sessions,
      projectsById,
      interval.startMs,
      interval.endMs,
      filter.grouping
    );

    const columns: ReportColumn[] =
      filter.selectedColumns.length > 0 ? filter.selectedColumns : DEFAULT_REPORT_COLUMNS;

    return {
      rows,
      totalDuration: detailedRows.reduce((acc, r) => acc + r.durationSeconds, 0),
      totalValue: detailedRows.reduce((acc, r) => acc + r.estimatedValue, 0),
      columns,
      periodLabel: REPORT_PERIOD_LABELS[filter.period]
    };
  }

  buildExportPayloads(
    filter: ReportFilter,
    logoDataUrl: string | null = null,
    referenceDate: Date = new Date()
  ): {
    title: string;
    csv: string;
    excelXml: string;
    pdfHtml: string;
  } {
    const result = this.generate(filter, referenceDate);
    const settings = this.settingsRepository.current();
    const metas = result.columns.map((col) => REPORT_COLUMN_META[col]);
    const headers = metas.map((m) => m.header);
    const tableRows = result.rows.map((row) =>
      result.columns.map((col) => formatReportColumnValue(col, row, settings.timeFormat))
    );
    const title = `Relatório — ${result.periodLabel}`;
    const nowIso = referenceDate.toISOString();
    const generatedAtText = `${formatShortDate(nowIso)} às ${formatShortTime(nowIso, settings.timeFormat)}`;

    return {
      title,
      csv: buildCsvContent(headers, tableRows),
      excelXml: buildExcelXmlContent(title, headers, tableRows),
      pdfHtml: buildReportPdfHtml({
        title,
        generatedAtText,
        columns: metas,
        rows: tableRows,
        totalDurationText: formatClock(result.totalDuration, false),
        totalValueText: formatCurrencyBRL(result.totalValue),
        logoDataUrl: settings.includeLogoInPDF ? logoDataUrl : null
      })
    };
  }
}
