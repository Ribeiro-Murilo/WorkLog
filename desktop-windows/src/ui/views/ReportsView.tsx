import React, { useCallback, useEffect, useState } from "react";
import { BarChart3, ChevronDown, Download, Save } from "lucide-react";
import { formatClock, formatCurrencyBRL } from "../../shared/format";
import {
  DEFAULT_REPORT_COLUMNS,
  REPORT_COLUMNS,
  REPORT_COLUMN_META,
  formatReportColumnValue
} from "../../shared/reports";
import {
  EXPORT_FORMAT_LABELS,
  PROJECT_CATEGORY_LABELS,
  REPORT_GROUPING_LABELS,
  REPORT_PERIOD_LABELS,
  SESSION_STATUS_LABELS,
  type AppSnapshot,
  type ExportFormat,
  type ProjectCategory,
  type ReportColumn,
  type ReportFilter,
  type ReportGrouping,
  type ReportPeriod,
  type ReportResult,
  type SessionStatus
} from "../../shared/types";

interface ReportsViewProps {
  snapshot: AppSnapshot;
}

function todayInputDate(): string {
  const d = new Date();
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, "0");
  const day = String(d.getDate()).padStart(2, "0");
  return `${y}-${m}-${day}`;
}

export const ReportsView: React.FC<ReportsViewProps> = ({ snapshot }) => {
  const [period, setPeriod] = useState<ReportPeriod>("today");
  const [customStart, setCustomStart] = useState(todayInputDate);
  const [customEnd, setCustomEnd] = useState(todayInputDate);
  const [projectId, setProjectId] = useState<string>("");
  const [category, setCategory] = useState<ProjectCategory | "">("");
  const [status, setStatus] = useState<SessionStatus | "">("");
  const [client, setClient] = useState("");
  const [tag, setTag] = useState("");
  const [grouping, setGrouping] = useState<ReportGrouping>("detailed");
  const [selectedColumns, setSelectedColumns] = useState<ReportColumn[]>(DEFAULT_REPORT_COLUMNS);
  const [showColumnsPopover, setShowColumnsPopover] = useState(false);
  const [showSavePresetModal, setShowSavePresetModal] = useState(false);
  const [newPresetName, setNewPresetName] = useState("");
  const [result, setResult] = useState<ReportResult | null>(null);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  const currentFilter = useCallback(
    (): ReportFilter => ({
      period,
      customStart,
      customEnd,
      projectId: projectId || null,
      client: client.trim() || null,
      category: category || null,
      status: status || null,
      tag: tag.trim() || null,
      selectedColumns,
      grouping
    }),
    [period, customStart, customEnd, projectId, client, category, status, tag, selectedColumns, grouping]
  );

  useEffect(() => {
    let active = true;
    void window.worklog.reports
      .generate(currentFilter())
      .then((res) => {
        if (active) {
          setResult(res);
          setErrorMessage(null);
        }
      })
      .catch((err) => {
        if (active) setErrorMessage(err instanceof Error ? err.message : String(err));
      });
    return () => {
      active = false;
    };
  }, [currentFilter, snapshot.sessions, snapshot.projects]);

  const toggleColumn = (col: ReportColumn) => {
    setSelectedColumns((prev) => {
      if (prev.includes(col)) {
        return prev.filter((c) => c !== col);
      }
      return REPORT_COLUMNS.map((m) => m.id).filter(
        (id) => prev.includes(id) || id === col
      );
    });
  };

  const handleExport = async (format: ExportFormat) => {
    try {
      setErrorMessage(null);
      await window.worklog.reports.export(currentFilter(), format);
    } catch (err) {
      setErrorMessage(err instanceof Error ? err.message : String(err));
    }
  };

  const activeColumns =
    selectedColumns.length > 0 ? selectedColumns : DEFAULT_REPORT_COLUMNS;

  return (
    <div>
      <div className="page-header">
        <h1 className="page-title">Relatórios</h1>
      </div>

      <div className="card" style={{ marginBottom: 16 }}>
        <div className="filters-row">
          <select
            className="select"
            value={period}
            onChange={(e) => setPeriod(e.target.value as ReportPeriod)}
          >
            {(Object.keys(REPORT_PERIOD_LABELS) as ReportPeriod[]).map((p) => (
              <option key={p} value={p}>
                {REPORT_PERIOD_LABELS[p]}
              </option>
            ))}
          </select>

          {period === "custom" && (
            <>
              <label className="small muted">De</label>
              <input
                className="input"
                type="date"
                value={customStart}
                onChange={(e) => setCustomStart(e.target.value)}
              />
              <label className="small muted">Até</label>
              <input
                className="input"
                type="date"
                value={customEnd}
                onChange={(e) => setCustomEnd(e.target.value)}
              />
            </>
          )}
        </div>

        <div className="filters-row">
          <select
            className="select"
            value={projectId}
            onChange={(e) => setProjectId(e.target.value)}
          >
            <option value="">Todos os projetos</option>
            {snapshot.projects.map((p) => (
              <option key={p.id} value={p.id}>
                {p.name}
              </option>
            ))}
          </select>

          <select
            className="select"
            value={category}
            onChange={(e) => setCategory(e.target.value as ProjectCategory | "")}
          >
            <option value="">Todas as categorias</option>
            {(Object.keys(PROJECT_CATEGORY_LABELS) as ProjectCategory[]).map((c) => (
              <option key={c} value={c}>
                {PROJECT_CATEGORY_LABELS[c]}
              </option>
            ))}
          </select>

          <select
            className="select"
            value={status}
            onChange={(e) => setStatus(e.target.value as SessionStatus | "")}
          >
            <option value="">Todos os status</option>
            {(Object.keys(SESSION_STATUS_LABELS) as SessionStatus[]).map((s) => (
              <option key={s} value={s}>
                {SESSION_STATUS_LABELS[s]}
              </option>
            ))}
          </select>

          <input
            className="input"
            type="text"
            placeholder="Cliente"
            style={{ width: 150 }}
            value={client}
            onChange={(e) => setClient(e.target.value)}
          />

          <input
            className="input"
            type="text"
            placeholder="Tag"
            style={{ width: 130 }}
            value={tag}
            onChange={(e) => setTag(e.target.value)}
          />
        </div>

        <div className="filters-row" style={{ marginBottom: 0 }}>
          <select
            className="select"
            value={grouping}
            onChange={(e) => setGrouping(e.target.value as ReportGrouping)}
          >
            {(Object.keys(REPORT_GROUPING_LABELS) as ReportGrouping[]).map((g) => (
              <option key={g} value={g}>
                {REPORT_GROUPING_LABELS[g]}
              </option>
            ))}
          </select>

          <div className="popover-anchor">
            <button
              type="button"
              className="btn"
              onClick={() => setShowColumnsPopover((prev) => !prev)}
            >
              Colunas <ChevronDown size={14} />
            </button>
            {showColumnsPopover && (
              <div className="popover-panel">
                <strong style={{ fontSize: 13, marginBottom: 4 }}>
                  Colunas do relatório
                </strong>
                {REPORT_COLUMNS.map((col) => (
                  <label key={col.id} className="checkbox-line">
                    <input
                      type="checkbox"
                      checked={selectedColumns.includes(col.id)}
                      onChange={() => toggleColumn(col.id)}
                    />
                    {col.header}
                  </label>
                ))}
              </div>
            )}
          </div>

          <select
            className="select"
            value=""
            onChange={(e) => {
              const preset = snapshot.presets.find((p) => p.id === e.target.value);
              if (preset) {
                setSelectedColumns(
                  preset.columns.length > 0 ? preset.columns : DEFAULT_REPORT_COLUMNS
                );
                setGrouping(preset.grouping);
              }
            }}
          >
            <option value="">Tipo salvo: Selecionar…</option>
            {snapshot.presets.map((preset) => (
              <option key={preset.id} value={preset.id}>
                {preset.name}
              </option>
            ))}
          </select>

          <button
            type="button"
            className="btn"
            onClick={() => setShowSavePresetModal(true)}
          >
            <Save size={14} /> Salvar tipo…
          </button>

          {snapshot.presets.length > 0 && (
            <select
              className="select"
              value=""
              onChange={(e) => {
                if (e.target.value) {
                  void window.worklog.reports.deletePreset(e.target.value);
                }
              }}
              aria-label="Excluir tipo salvo"
            >
              <option value="">Excluir tipo…</option>
              {snapshot.presets.map((preset) => (
                <option key={preset.id} value={preset.id}>
                  Excluir {preset.name}
                </option>
              ))}
            </select>
          )}
        </div>
      </div>

      {errorMessage && (
        <div className="alert-banner alert-error" style={{ marginBottom: 14 }}>
          {errorMessage}
        </div>
      )}

      <div className="table-wrap" style={{ marginBottom: 16 }}>
        {!result || result.rows.length === 0 ? (
          <div className="empty-state">
            <BarChart3 size={28} />
            <strong>Nenhuma sessão no período</strong>
            <span className="small">
              Ajuste os filtros para visualizar sessões registradas.
            </span>
          </div>
        ) : (
          <table className="data-table">
            <thead>
              <tr>
                {activeColumns.map((col) => (
                  <th
                    key={col}
                    style={{
                      textAlign:
                        REPORT_COLUMN_META[col].pdfAlignment === "trailing"
                          ? "right"
                          : "left"
                    }}
                  >
                    {REPORT_COLUMN_META[col].header}
                  </th>
                ))}
              </tr>
            </thead>
            <tbody>
              {result.rows.map((row) => (
                <tr key={row.id}>
                  {activeColumns.map((col) => (
                    <td
                      key={col}
                      className="tabular"
                      style={{
                        textAlign:
                          REPORT_COLUMN_META[col].pdfAlignment === "trailing"
                            ? "right"
                            : "left"
                      }}
                    >
                      {formatReportColumnValue(col, row, snapshot.settings.timeFormat)}
                    </td>
                  ))}
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>

      <div
        className="card"
        style={{
          display: "flex",
          alignItems: "center",
          justifyContent: "space-between",
          flexWrap: "wrap",
          gap: 12
        }}
      >
        <div style={{ display: "flex", gap: 20, fontSize: 15, fontWeight: 600 }}>
          <span className="tabular">
            Total: {formatClock(result?.totalDuration ?? 0, false)}
          </span>
          <span className="tabular">
            Valor: {formatCurrencyBRL(result?.totalValue ?? 0)}
          </span>
        </div>

        <div className="toolbar-actions">
          {(["csv", "excel", "pdf"] as ExportFormat[]).map((format) => (
            <button
              key={format}
              type="button"
              className="btn"
              onClick={() => void handleExport(format)}
            >
              <Download size={14} /> {EXPORT_FORMAT_LABELS[format]}
            </button>
          ))}
        </div>
      </div>

      {showSavePresetModal && (
        <div className="modal-backdrop" onClick={() => setShowSavePresetModal(false)}>
          <div
            className="modal-card"
            style={{ maxWidth: 400 }}
            onClick={(e) => e.stopPropagation()}
          >
            <div className="modal-header">
              <h3>Salvar tipo de relatório</h3>
            </div>
            <div className="modal-body">
              <p className="small muted" style={{ margin: 0 }}>
                As colunas e o agrupamento atuais serão salvos com este nome.
              </p>
              <input
                className="input"
                type="text"
                placeholder="Nome"
                value={newPresetName}
                onChange={(e) => setNewPresetName(e.target.value)}
                autoFocus
              />
            </div>
            <div className="modal-footer">
              <button
                type="button"
                className="btn"
                onClick={() => {
                  setNewPresetName("");
                  setShowSavePresetModal(false);
                }}
              >
                Cancelar
              </button>
              <button
                type="button"
                className="btn btn-primary"
                disabled={!newPresetName.trim()}
                onClick={() => {
                  const name = newPresetName.trim();
                  setNewPresetName("");
                  setShowSavePresetModal(false);
                  void window.worklog.reports.savePreset(name, activeColumns, grouping);
                }}
              >
                Salvar
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};
