import {
  formatClock,
  formatCurrency,
  formatShortDate,
  formatShortTime
} from "./format";
import type { CurrencyCode } from "./currency";
import {
  calculateSessionValue,
  getRecordedSlices,
  startOfLocalDay
} from "./periods";
import {
  PROJECT_CATEGORY_LABELS,
  SESSION_STATUS_LABELS,
  type InvoiceLineItem,
  type Project,
  type ReportColumn,
  type ReportGrouping,
  type ReportRow,
  type Session,
  type TimeFormatPreference
} from "./types";

export interface ReportColumnMeta {
  id: ReportColumn;
  header: string;
  pdfAlignment: "leading" | "trailing";
  pdfWeight: number;
}

export const REPORT_COLUMNS: ReportColumnMeta[] = [
  { id: "project", header: "Projeto", pdfAlignment: "leading", pdfWeight: 1.4 },
  { id: "client", header: "Cliente", pdfAlignment: "leading", pdfWeight: 1.4 },
  { id: "date", header: "Data", pdfAlignment: "leading", pdfWeight: 1 },
  { id: "startTime", header: "Início", pdfAlignment: "leading", pdfWeight: 1 },
  { id: "endTime", header: "Fim", pdfAlignment: "leading", pdfWeight: 1 },
  { id: "duration", header: "Duração", pdfAlignment: "trailing", pdfWeight: 1 },
  { id: "sessionCount", header: "Nº de sessões", pdfAlignment: "trailing", pdfWeight: 1 },
  { id: "category", header: "Categoria", pdfAlignment: "leading", pdfWeight: 1 },
  { id: "status", header: "Status", pdfAlignment: "leading", pdfWeight: 1 },
  { id: "value", header: "Valor", pdfAlignment: "trailing", pdfWeight: 1 },
  { id: "note", header: "Observação", pdfAlignment: "leading", pdfWeight: 2 },
  { id: "tags", header: "Tags", pdfAlignment: "leading", pdfWeight: 1.4 },
  { id: "description", header: "Descrição", pdfAlignment: "leading", pdfWeight: 2 }
];

export const DEFAULT_REPORT_COLUMNS: ReportColumn[] = [
  "project",
  "client",
  "date",
  "startTime",
  "endTime",
  "duration",
  "category",
  "status",
  "value",
  "note"
];

export const REPORT_COLUMN_META: Record<ReportColumn, ReportColumnMeta> = Object.fromEntries(
  REPORT_COLUMNS.map((col) => [col.id, col])
) as Record<ReportColumn, ReportColumnMeta>;

export function formatReportColumnValue(
  column: ReportColumn,
  row: ReportRow,
  timeFormat: TimeFormatPreference = "twentyFourHour"
): string {
  switch (column) {
    case "project":
      return row.projectName;
    case "client":
      return row.client;
    case "date":
      return formatShortDate(row.date);
    case "startTime":
      return formatShortTime(row.startTime, timeFormat);
    case "endTime":
      return row.endTime ? formatShortTime(row.endTime, timeFormat) : "—";
    case "duration":
      return formatClock(row.durationSeconds, true);
    case "sessionCount":
      return String(row.sessionCount);
    case "category":
      return PROJECT_CATEGORY_LABELS[row.category];
    case "status":
      return SESSION_STATUS_LABELS[row.status];
    case "value":
      return formatCurrency(row.estimatedValue, row.currencyCode, true);
    case "note":
      return row.note;
    case "tags":
      return row.tags.join(", ");
    case "description":
      return row.descriptionText;
  }
}

export function buildDetailedReportRows(
  sessions: Session[],
  projectsById: Map<string, Project>,
  intervalStartMs: number,
  intervalEndMs: number
): ReportRow[] {
  const rows: ReportRow[] = [];
  for (const session of sessions) {
    const project = session.projectId ? projectsById.get(session.projectId) : undefined;
    const slices = getRecordedSlices(session, intervalStartMs, intervalEndMs);
    slices.forEach((slice, index) => {
      const rate = project?.dailyRate ?? 0;
      const estimatedValue = calculateSessionValue(slice.durationSeconds, rate);
      const sliceDate = startOfLocalDay(new Date(slice.startMs)).toISOString();
      rows.push({
        id: `${session.id}#${index}`,
        projectName: project?.name ?? "—",
        client: project?.client ?? "—",
        date: sliceDate,
        startTime: new Date(slice.startMs).toISOString(),
        endTime: new Date(slice.endMs).toISOString(),
        durationSeconds: slice.durationSeconds,
        category: session.category,
        status: session.status,
        estimatedValue,
        currencyCode: project?.currencyCode ?? "BRL",
        note: session.note,
        tags: project?.tags ?? [],
        descriptionText: project?.descriptionText ?? "",
        sessionCount: 1
      });
    });
  }
  return rows;
}

export function buildReportRows(
  sessions: Session[],
  projectsById: Map<string, Project>,
  intervalStartMs: number,
  intervalEndMs: number,
  grouping: ReportGrouping
): { rows: ReportRow[]; detailedRows: ReportRow[] } {
  const detailedRows = buildDetailedReportRows(sessions, projectsById, intervalStartMs, intervalEndMs);
  if (grouping === "detailed") {
    return { rows: detailedRows, detailedRows };
  }

  const projectIdBySessionId = new Map<string, string>();
  for (const session of sessions) {
    projectIdBySessionId.set(session.id, session.projectId ?? "—");
  }

  const order: string[] = [];
  const buckets = new Map<string, ReportRow[]>();

  for (const row of detailedRows) {
    const sessionId = row.id.split("#")[0];
    const projectId = projectIdBySessionId.get(sessionId) ?? "—";
    const dayKey = startOfLocalDay(new Date(row.date)).getTime();
    const key = `${projectId}#${dayKey}`;
    if (!buckets.has(key)) {
      buckets.set(key, []);
      order.push(key);
    }
    buckets.get(key)!.push(row);
  }

  const grouped: ReportRow[] = [];
  for (const key of order) {
    const group = buckets.get(key)!;
    const first = group[0];
    const sessionIds = new Set(group.map((r) => r.id.split("#")[0]));
    const seenNoteSessions = new Set<string>();
    const notes: string[] = [];
    for (const item of group) {
      const sid = item.id.split("#")[0];
      if (seenNoteSessions.has(sid)) continue;
      seenNoteSessions.add(sid);
      if (item.note.trim().length > 0) {
        notes.push(item.note);
      }
    }

    const startTime = group.reduce(
      (min, item) => (Date.parse(item.startTime) < Date.parse(min) ? item.startTime : min),
      first.startTime
    );
    const endTimes = group.map((item) => item.endTime).filter((v): v is string => Boolean(v));
    const endTime =
      endTimes.length > 0
        ? endTimes.reduce((max, item) => (Date.parse(item) > Date.parse(max) ? item : max), endTimes[0])
        : null;

    grouped.push({
      id: key,
      projectName: first.projectName,
      client: first.client,
      date: first.date,
      startTime,
      endTime,
      durationSeconds: group.reduce((acc, item) => acc + item.durationSeconds, 0),
      category: first.category,
      status: first.status,
      currencyCode: first.currencyCode,
      estimatedValue: group.reduce((acc, item) => acc + item.estimatedValue, 0),
      note: notes.join(" | "),
      tags: first.tags,
      descriptionText: first.descriptionText,
      sessionCount: sessionIds.size
    });
  }

  return { rows: grouped, detailedRows };
}

export function buildCsvContent(headers: string[], rows: string[][]): string {
  const escape = (value: string) => {
    if (value.includes(",") || value.includes("\"") || value.includes("\n") || value.includes("\r")) {
      return `"${value.replace(/"/g, "\"\"")}"`;
    }
    return value;
  };
  const lines = [
    headers.map(escape).join(","),
    ...rows.map((row) => row.map(escape).join(","))
  ];
  return "\uFEFF" + lines.join("\r\n");
}

function xmlEscape(value: string): string {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

export function buildExcelXmlContent(title: string, headers: string[], rows: string[][]): string {
  const headerCells = headers
    .map((h) => `<Cell><Data ss:Type="String">${xmlEscape(h)}</Data></Cell>`)
    .join("");
  const bodyRows = rows
    .map((row) => {
      const cells = row
        .map((v) => `<Cell><Data ss:Type="String">${xmlEscape(v)}</Data></Cell>`)
        .join("");
      return `\n   <Row>${cells}</Row>`;
    })
    .join("");

  return [
    `<?xml version="1.0"?>`,
    `<?mso-application progid="Excel.Sheet"?>`,
    `<Workbook xmlns="urn:schemas-microsoft-com:office:spreadsheet"`,
    ` xmlns:o="urn:schemas-microsoft-com:office:office"`,
    ` xmlns:x="urn:schemas-microsoft-com:office:excel"`,
    ` xmlns:ss="urn:schemas-microsoft-com:office:spreadsheet">`,
    ` <Worksheet ss:Name="${xmlEscape(title)}">`,
    `  <Table>`,
    `\n   <Row>${headerCells}</Row>${bodyRows}`,
    `\n  </Table>`,
    ` </Worksheet>`,
    `</Workbook>`
  ].join("\n");
}

function htmlEscape(value: string): string {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

export function buildReportPdfHtml(params: {
  title: string;
  generatedAtText: string;
  columns: ReportColumnMeta[];
  rows: string[][];
  totalDurationText: string;
  totalValueText: string | null;
  logoDataUrl: string | null;
}): string {
  const totalWeight = params.columns.reduce((acc, col) => acc + col.pdfWeight, 0) || 1;
  const colGroup = params.columns
    .map((col) => `<col style="width: ${((col.pdfWeight / totalWeight) * 100).toFixed(2)}%;" />`)
    .join("");
  const ths = params.columns
    .map(
      (col) =>
        `<th class="${col.pdfAlignment === "trailing" ? "num" : "txt"}">${htmlEscape(col.header)}</th>`
    )
    .join("");
  const trs = params.rows
    .map((row) => {
      const tds = params.columns
        .map(
          (col, i) =>
            `<td class="${col.pdfAlignment === "trailing" ? "num" : "txt"}">${htmlEscape(row[i] ?? "")}</td>`
        )
        .join("");
      return `<tr>${tds}</tr>`;
    })
    .join("");

  const logoHtml = params.logoDataUrl
    ? `<img src="${params.logoDataUrl}" class="logo" alt="WorkLog" />`
    : "";

  return `<!doctype html>
<html lang="pt-BR">
<head>
<meta charset="UTF-8" />
<style>
  @page { size: A4; margin: 42px; }
  body { font-family: "Segoe UI", system-ui, sans-serif; color: #212121; font-size: 10px; margin: 0; }
  .letterhead { display: flex; justify-content: space-between; align-items: flex-start; border-bottom: 2px solid #2B3D6B; padding-bottom: 12px; margin-bottom: 16px; }
  .logo { width: 42px; height: 42px; border-radius: 8px; margin-bottom: 10px; display: block; }
  h1 { font-size: 18px; margin: 0 0 4px; color: #212121; }
  .meta { color: #6B6B6B; font-size: 9.5px; margin: 0; }
  table { width: 100%; border-collapse: collapse; table-layout: fixed; }
  th { font-size: 8.5px; text-transform: uppercase; letter-spacing: 0.4px; color: #6B6B6B; border-bottom: 1px solid #2B3D6B; padding: 6px 4px; }
  td { font-size: 9.5px; padding: 7px 4px; border-bottom: 0.5px solid #E0E0E0; word-wrap: break-word; font-variant-numeric: tabular-nums; }
  .txt { text-align: left; }
  .num { text-align: right; }
  .summary { margin-top: 14px; display: flex; justify-content: flex-end; gap: 24px; font-weight: 600; font-size: 11px; color: #2B3D6B; }
  .footer { margin-top: 22px; font-size: 8px; color: #6B6B6B; text-align: right; }
</style>
</head>
<body>
  <div class="letterhead">
    <div>
      ${logoHtml}
      <h1>${htmlEscape(params.title)}</h1>
      <p class="meta">Gerado em ${htmlEscape(params.generatedAtText)}</p>
    </div>
  </div>
  <table>
    <colgroup>${colGroup}</colgroup>
    <thead><tr>${ths}</tr></thead>
    <tbody>${trs}</tbody>
  </table>
  <div class="summary">
    <span>Total: ${htmlEscape(params.totalDurationText)}</span>
    ${params.totalValueText ? `<span>Valor: ${htmlEscape(params.totalValueText)}</span>` : ""}
  </div>
  <div class="footer">WorkLog</div>
</body>
</html>`;
}

export function buildInvoicePdfHtml(params: {
  issuerName: string;
  issuerDetails: string;
  invoiceNumber: string;
  issueDateText: string;
  periodStartText: string;
  periodEndText: string;
  client: string;
  lineItems: InvoiceLineItem[];
  currencyCode: CurrencyCode;
  totalDurationText: string;
  totalValueText: string;
  notes: string;
  logoDataUrl: string | null;
}): string {
  const logoHtml = params.logoDataUrl
    ? `<img src="${params.logoDataUrl}" class="logo" alt="WorkLog" />`
    : "";
  const rowsHtml = params.lineItems
    .map(
      (item) => `<tr>
        <td>${htmlEscape(formatShortDate(item.date))}</td>
        <td>${htmlEscape(item.projectName)}</td>
        <td class="num">${htmlEscape(formatClock(item.durationSeconds, false))}</td>
        <td class="num">${htmlEscape(formatCurrency(item.value, params.currencyCode, true))}</td>
      </tr>`
    )
    .join("");

  return `<!doctype html>
<html lang="pt-BR">
<head>
<meta charset="UTF-8" />
<style>
  @page { size: A4; margin: 48px; }
  body { font-family: "Segoe UI", system-ui, sans-serif; color: #212121; font-size: 10px; margin: 0; }
  .letterhead { display: flex; justify-content: space-between; align-items: flex-start; border-bottom: 2px solid #2B3D6B; padding-bottom: 14px; margin-bottom: 16px; }
  .left { max-width: 56%; }
  .right { text-align: right; max-width: 42%; }
  .logo { width: 42px; height: 42px; border-radius: 8px; margin-bottom: 10px; display: block; }
  .issuer-name { font-size: 16px; font-weight: 700; margin: 0 0 4px; }
  .issuer-details { font-size: 9.5px; color: #6B6B6B; white-space: pre-line; margin: 0; }
  .label { font-size: 8.5px; font-weight: 700; letter-spacing: 1px; color: #2B3D6B; text-transform: uppercase; margin: 0 0 4px; }
  .inv-num { font-size: 15px; font-weight: 700; margin: 0 0 6px; }
  .meta { font-size: 9.5px; color: #6B6B6B; margin: 0 0 2px; }
  .subhead { margin-bottom: 18px; }
  .client-name { font-size: 13px; font-weight: 700; margin: 0; }
  table { width: 100%; border-collapse: collapse; }
  th { font-size: 8.5px; text-transform: uppercase; letter-spacing: 0.4px; color: #6B6B6B; border-bottom: 1px solid #2B3D6B; padding: 7px 4px; text-align: left; }
  td { font-size: 9.5px; padding: 8px 4px; border-bottom: 0.5px solid #E0E0E0; font-variant-numeric: tabular-nums; }
  .num { text-align: right; }
  tr.total-row td { background: rgba(43, 61, 107, 0.06); border-top: 1.5px solid #2B3D6B; border-bottom: 1.5px solid #2B3D6B; font-weight: 700; font-size: 10.5px; }
  tr.total-row td.num { color: #2B3D6B; }
  .notes { margin-top: 20px; font-size: 9px; color: #444; white-space: pre-line; }
  .footer { margin-top: 26px; font-size: 8px; color: #6B6B6B; text-align: right; }
</style>
</head>
<body>
  <div class="letterhead">
    <div class="left">
      ${logoHtml}
      ${params.issuerName ? `<p class="issuer-name">${htmlEscape(params.issuerName)}</p>` : ""}
      ${params.issuerDetails ? `<p class="issuer-details">${htmlEscape(params.issuerDetails)}</p>` : ""}
    </div>
    <div class="right">
      <p class="label">NOTA DE FATURAMENTO</p>
      <p class="inv-num">${htmlEscape(params.invoiceNumber)}</p>
      <p class="meta">Emitida em ${htmlEscape(params.issueDateText)}</p>
      <p class="meta">Período: ${htmlEscape(params.periodStartText)} a ${htmlEscape(params.periodEndText)}</p>
    </div>
  </div>
  <div class="subhead">
    <p class="label">FATURADO A</p>
    <p class="client-name">${htmlEscape(params.client)}</p>
  </div>
  <table>
    <thead>
      <tr>
        <th style="width: 22%">Data</th>
        <th style="width: 36%">Projeto</th>
        <th class="num" style="width: 21%">Duração</th>
        <th class="num" style="width: 21%">Valor</th>
      </tr>
    </thead>
    <tbody>
      ${rowsHtml}
      <tr class="total-row">
        <td></td>
        <td>Total</td>
        <td class="num">${htmlEscape(params.totalDurationText)}</td>
        <td class="num">${htmlEscape(params.totalValueText)}</td>
      </tr>
    </tbody>
  </table>
  ${params.notes ? `<div class="notes">${htmlEscape(params.notes)}</div>` : ""}
  <div class="footer">WorkLog</div>
</body>
</html>`;
}
