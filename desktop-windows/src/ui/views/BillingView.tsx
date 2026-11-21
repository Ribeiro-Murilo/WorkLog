import React, { useEffect, useState } from "react";
import { AlertTriangle, FileDown, FileText, Trash2 } from "lucide-react";
import { CURRENCIES, type CurrencyCode } from "../../shared/currency";
import { formatClock, formatCurrency, formatShortDate } from "../../shared/format";
import {
  INVOICE_STATUS_LABELS,
  REPORT_PERIOD_LABELS,
  type AppSnapshot,
  type BillingPreview,
  type Invoice,
  type ReportPeriod
} from "../../shared/types";
import { ConfirmModal } from "../modals/ConfirmModal";

interface BillingViewProps {
  snapshot: AppSnapshot;
}

function todayInputDate(): string {
  const d = new Date();
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, "0");
  const day = String(d.getDate()).padStart(2, "0");
  return `${y}-${m}-${day}`;
}

export const BillingView: React.FC<BillingViewProps> = ({ snapshot }) => {
  const [clients, setClients] = useState<string[]>([]);
  const [selectedClient, setSelectedClient] = useState<string>("");
  const [preferredCurrency, setPreferredCurrency] = useState<CurrencyCode | null>(null);
  const [period, setPeriod] = useState<ReportPeriod>("month");
  const [customStart, setCustomStart] = useState(todayInputDate);
  const [customEnd, setCustomEnd] = useState(todayInputDate);
  const [notes, setNotes] = useState("");
  const [preview, setPreview] = useState<BillingPreview | null>(null);
  const [deletingInvoice, setDeletingInvoice] = useState<Invoice | null>(null);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  useEffect(() => {
    let active = true;
    void window.worklog.billing.availableClients().then((list) => {
      if (!active) return;
      setClients(list);
      if (!selectedClient && list.length > 0) {
        setSelectedClient(list[0]);
      }
    });
    return () => {
      active = false;
    };
  }, [snapshot.projects, selectedClient]);

  const clientCurrencies = CURRENCIES.filter((currency) =>
    snapshot.projects.some((project) => project.client === selectedClient && project.currencyCode === currency)
  );
  const selectedCurrency = preferredCurrency && clientCurrencies.includes(preferredCurrency)
    ? preferredCurrency : clientCurrencies[0] ?? "BRL";

  useEffect(() => {
    let active = true;
    setPreview(null);
    void window.worklog.billing.preview({
      client: selectedClient || null,
      currencyCode: selectedCurrency,
      period,
      customStart,
      customEnd
    }).then((data) => {
      if (active) setPreview(data);
    }).catch((err) => {
      if (active) setErrorMessage(err instanceof Error ? err.message : String(err));
    });
    return () => { active = false; };
  }, [selectedClient, selectedCurrency, period, customStart, customEnd,
      snapshot.projects, snapshot.sessions, snapshot.invoices]);

  const handleGenerate = async () => {
    if (!selectedClient) return;
    try {
      setErrorMessage(null);
      await window.worklog.billing.generateInvoice({
        client: selectedClient,
        currencyCode: selectedCurrency,
        period,
        customStart,
        customEnd,
        notes
      });
      setNotes("");
    } catch (err) {
      setErrorMessage(err instanceof Error ? err.message : String(err));
    }
  };

  return (
    <div>
      <div className="page-header">
        <h1 className="page-title">Faturamento</h1>
      </div>

      {errorMessage && (
        <div className="alert-banner alert-error" style={{ marginBottom: 14 }}>
          {errorMessage}
        </div>
      )}

      <div className="card" style={{ marginBottom: 20 }}>
        <h2 className="section-title">Nova fatura</h2>

        <div className="filters-row">
          <select
            className="select"
            value={selectedClient}
            onChange={(e) => setSelectedClient(e.target.value)}
          >
            {clients.length === 0 ? (
              <option value="">Nenhum cliente cadastrado</option>
            ) : (
              clients.map((c) => (
                <option key={c} value={c}>
                  {c}
                </option>
              ))
            )}
          </select>

          <select
            className="select"
            aria-label="Moeda da fatura"
            value={selectedCurrency}
            disabled={clientCurrencies.length <= 1}
            onChange={(e) => setPreferredCurrency(e.target.value as CurrencyCode)}
          >
            {(clientCurrencies.length ? clientCurrencies : ["BRL"]).map((currency) => (
              <option key={currency}>{currency}</option>
            ))}
          </select>

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

        <div className="table-wrap" style={{ marginBottom: 12 }}>
          {!preview || preview.lineItems.length === 0 ? (
            <div className="empty-state">
              <FileText size={26} />
              <strong>Nenhuma sessão no período</strong>
              <span className="small">
                Selecione um cliente, uma moeda e um período com sessões encerradas.
              </span>
            </div>
          ) : (
            <table className="data-table">
              <thead>
                <tr>
                  <th>Data</th>
                  <th>Projeto</th>
                  <th style={{ textAlign: "right" }}>Duração</th>
                  <th style={{ textAlign: "right" }}>Valor</th>
                </tr>
              </thead>
              <tbody>
                {preview.lineItems.map((item, idx) => (
                  <tr key={`${item.date}-${item.projectName}-${idx}`}>
                    <td>{formatShortDate(item.date)}</td>
                    <td>{item.projectName}</td>
                    <td className="tabular" style={{ textAlign: "right" }}>
                      {formatClock(item.durationSeconds, false)}
                    </td>
                    <td className="tabular" style={{ textAlign: "right" }}>
                      {formatCurrency(item.value, preview.currencyCode, true)}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </div>

        {preview?.overlapsExistingInvoice && (
          <div className="alert-banner alert-warning" style={{ marginBottom: 12 }}>
            <AlertTriangle size={16} />
            Já existe uma fatura deste cliente em {preview.currencyCode} com período sobreposto a este.
          </div>
        )}

        <div
          style={{
            display: "flex",
            alignItems: "center",
            justifyContent: "space-between",
            flexWrap: "wrap",
            gap: 12
          }}
        >
          <div style={{ display: "flex", gap: 18, fontSize: 15, fontWeight: 600 }}>
            <span className="tabular">
              Total: {formatClock(preview?.totalDurationSeconds ?? 0, false)}
            </span>
            <span className="tabular">
              Valor: {formatCurrency(preview?.totalValue ?? 0, selectedCurrency, true)}
            </span>
          </div>

          <div className="toolbar-actions">
            <input
              className="input"
              type="text"
              placeholder="Observações (opcional)"
              style={{ width: 220 }}
              value={notes}
              onChange={(e) => setNotes(e.target.value)}
            />
            <button
              type="button"
              className="btn btn-primary"
              disabled={
                !preview ||
                preview.client !== selectedClient ||
                preview.currencyCode !== selectedCurrency ||
                preview.lineItems.length === 0 ||
                preview.overlapsExistingInvoice
              }
              onClick={() => void handleGenerate()}
            >
              Gerar fatura
            </button>
          </div>
        </div>
      </div>

      <div className="card">
        <h2 className="section-title">Histórico</h2>
        <div className="table-wrap">
          {snapshot.invoices.length === 0 ? (
            <div className="empty-state">
              <FileText size={26} />
              <strong>Nenhuma fatura emitida</strong>
              <span className="small">Gere uma fatura acima para vê-la aqui.</span>
            </div>
          ) : (
            <table className="data-table">
              <thead>
                <tr>
                  <th>Nº</th>
                  <th>Cliente</th>
                  <th>Período</th>
                  <th style={{ textAlign: "right" }}>Valor</th>
                  <th>Status</th>
                  <th>Ações</th>
                </tr>
              </thead>
              <tbody>
                {snapshot.invoices.map((invoice) => (
                  <tr key={invoice.id}>
                    <td className="mono">{invoice.formattedNumber}</td>
                    <td>{invoice.client}</td>
                    <td className="tabular">
                      {formatShortDate(invoice.periodStart)} –{" "}
                      {formatShortDate(invoice.periodEnd)}
                    </td>
                    <td className="tabular" style={{ textAlign: "right" }}>
                      {formatCurrency(invoice.totalValue, invoice.currencyCode, true)}
                    </td>
                    <td>
                      <button
                        type="button"
                        className={`badge ${
                          invoice.status === "paid" ? "badge-success" : "badge-warning"
                        }`}
                        style={{ cursor: "pointer" }}
                        onClick={() =>
                          void window.worklog.billing.toggleStatus(invoice.id)
                        }
                      >
                        {INVOICE_STATUS_LABELS[invoice.status]}
                      </button>
                    </td>
                    <td>
                      <div style={{ display: "flex", gap: 6 }}>
                        <button
                          type="button"
                          className="btn btn-icon"
                          title="Exportar PDF"
                          onClick={() =>
                            void window.worklog.billing
                              .exportPdf(invoice.id)
                              .catch((err) => setErrorMessage(String(err)))
                          }
                        >
                          <FileDown size={14} />
                        </button>
                        <button
                          type="button"
                          className="btn btn-icon btn-danger"
                          title="Excluir fatura"
                          onClick={() => setDeletingInvoice(invoice)}
                        >
                          <Trash2 size={14} />
                        </button>
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </div>
      </div>

      {deletingInvoice && (
        <ConfirmModal
          title="Excluir fatura?"
          message={`A fatura ${deletingInvoice.formattedNumber} será removida permanentemente.`}
          onCancel={() => setDeletingInvoice(null)}
          onConfirm={() => {
            const id = deletingInvoice.id;
            setDeletingInvoice(null);
            void window.worklog.billing.deleteInvoice(id);
          }}
        />
      )}
    </div>
  );
};
