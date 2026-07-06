import fs from "node:fs";
import type { BackupPayload, ExportFormat, ExportTable, Project, Session } from "../../src/shared/types";
import { ProjectRepository } from "./projectRepository";
import { SessionRepository } from "./sessionRepository";
import { SettingsRepository } from "./settingsRepository";

export class BackupService {
  constructor(
    private readonly projects: ProjectRepository,
    private readonly sessions: SessionRepository,
    private readonly settings: SettingsRepository
  ) {}

  exportBackup(filePath: string): BackupPayload {
    const payload: BackupPayload = {
      exportedAt: new Date().toISOString(),
      projects: this.projects.fetchAll(true),
      sessions: this.sessions.fetchAll()
    };
    fs.writeFileSync(filePath, JSON.stringify(payload, null, 2), "utf8");
    this.settings.update({ lastBackupDate: payload.exportedAt });
    return payload;
  }

  importBackup(filePath: string): BackupPayload {
    const payload = JSON.parse(fs.readFileSync(filePath, "utf8")) as BackupPayload;
    for (const project of payload.projects) {
      this.upsertProject(project);
    }
    for (const session of payload.sessions) {
      this.upsertSession(session);
    }
    this.settings.update({ lastBackupDate: new Date().toISOString() });
    return payload;
  }

  exportTable(table: ExportTable, format: ExportFormat, filePath: string): void {
    const content = format === "csv" ? toCsv(table) : toExcelXml(table);
    fs.writeFileSync(filePath, content, "utf8");
  }

  private upsertProject(project: Project): void {
    this.projects.upsertRestored(project);
  }

  private upsertSession(session: Session): void {
    this.sessions.upsertRestored(session);
  }
}

function toCsv(table: ExportTable): string {
  const lines = [table.headers.map(csvField).join(",")];
  for (const row of table.rows) {
    lines.push(row.map(csvField).join(","));
  }
  return `\uFEFF${lines.join("\r\n")}`;
}

function csvField(value: string): string {
  return /[",\n]/.test(value) ? `"${value.replaceAll('"', '""')}"` : value;
}

function toExcelXml(table: ExportTable): string {
  const rows = [table.headers, ...table.rows]
    .map((row) => `   <Row>${row.map((value) => `<Cell><Data ss:Type="String">${xmlEscape(value)}</Data></Cell>`).join("")}</Row>`)
    .join("\n");
  return `<?xml version="1.0"?>
<?mso-application progid="Excel.Sheet"?>
<Workbook xmlns="urn:schemas-microsoft-com:office:spreadsheet"
 xmlns:o="urn:schemas-microsoft-com:office:office"
 xmlns:x="urn:schemas-microsoft-com:office:excel"
 xmlns:ss="urn:schemas-microsoft-com:office:spreadsheet">
 <Worksheet ss:Name="${xmlEscape(table.title)}">
  <Table>
${rows}
  </Table>
 </Worksheet>
</Workbook>`;
}

function xmlEscape(value: string): string {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
}
