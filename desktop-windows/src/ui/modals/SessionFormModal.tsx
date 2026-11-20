import React, { useEffect, useMemo, useState } from "react";
import { X } from "lucide-react";
import {
  formatClock,
  formatDateTimeSeconds,
  formatDateTimeShort
} from "../../shared/format";
import type {
  AvailabilityCheck,
  Project,
  SessionWithProject,
  SessionWorkPeriod,
  TimeFormatPreference
} from "../../shared/types";

interface SessionFormModalProps {
  project: Project;
  session: SessionWithProject | null;
  timeFormat: TimeFormatPreference;
  onClose: () => void;
  onSaved: () => void;
}

function toLocalDateInput(iso: string): string {
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return "";
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, "0");
  const day = String(d.getDate()).padStart(2, "0");
  return `${y}-${m}-${day}`;
}

function toLocalDateTimeInput(iso: string): string {
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return "";
  const datePart = toLocalDateInput(iso);
  const hh = String(d.getHours()).padStart(2, "0");
  const mm = String(d.getMinutes()).padStart(2, "0");
  const ss = String(d.getSeconds()).padStart(2, "0");
  return `${datePart}T${hh}:${mm}:${ss}`;
}

function parseLocalInputToIso(val: string): string | null {
  if (!val) return null;
  const d = new Date(val);
  return Number.isNaN(d.getTime()) ? null : d.toISOString();
}

export const SessionFormModal: React.FC<SessionFormModalProps> = ({
  project,
  session,
  timeFormat,
  onClose,
  onSaved
}) => {
  const isEditing = Boolean(session);
  const isTimeEditingLocked = session?.status === "running";
  const sourcePeriods = useMemo(
    () => session?.normalizedPeriods ?? [],
    [session]
  );
  const usesCycleEditor = isEditing && sourcePeriods.length > 1;

  const initialStartIso = session?.startTime ?? new Date(Date.now() - 3600_000).toISOString();
  const initialEndIso = session?.endTime ?? new Date().toISOString();

  const [dateValue, setDateValue] = useState(() => toLocalDateInput(initialStartIso));
  const [startValue, setStartValue] = useState(() => toLocalDateTimeInput(initialStartIso));
  const [endValue, setEndValue] = useState(() => toLocalDateTimeInput(initialEndIso));
  const [cyclePeriods, setCyclePeriods] = useState<SessionWorkPeriod[]>(() =>
    sourcePeriods.map((p) => ({ ...p }))
  );
  const [note, setNote] = useState(session?.note ?? "");
  const [availability, setAvailability] = useState<AvailabilityCheck | null>(null);
  const [availabilityError, setAvailabilityError] = useState<string | null>(null);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);

  const cyclesTotal = useMemo(
    () =>
      cyclePeriods.reduce((acc, p) => {
        const s = Date.parse(p.start);
        const e = Date.parse(p.end ?? p.start);
        return acc + Math.max(0, (e - s) / 1000);
      }, 0),
    [cyclePeriods]
  );

  useEffect(() => {
    if (isTimeEditingLocked) return;
    let active = true;
    const run = async () => {
      try {
        setAvailabilityError(null);
        if (usesCycleEditor) {
          const res = await window.worklog.sessions.checkAvailability({
            startTime: cyclePeriods[0]?.start ?? initialStartIso,
            endTime: cyclePeriods[cyclePeriods.length - 1]?.end ?? initialEndIso,
            excludingSessionId: session?.id ?? null,
            workPeriods: cyclePeriods
          });
          if (active) setAvailability(res);
          return;
        }
        const sIso = parseLocalInputToIso(startValue);
        const eIso = parseLocalInputToIso(endValue);
        if (!sIso || !eIso || Date.parse(eIso) <= Date.parse(sIso)) {
          if (active) setAvailability(null);
          return;
        }
        const res = await window.worklog.sessions.checkAvailability({
          startTime: sIso,
          endTime: eIso,
          excludingSessionId: session?.id ?? null
        });
        if (active) setAvailability(res);
      } catch (err) {
        if (active) {
          setAvailabilityError(
            `Não foi possível consultar os horários: ${err instanceof Error ? err.message : String(err)}`
          );
        }
      }
    };
    void run();
    return () => {
      active = false;
    };
  }, [startValue, endValue, cyclePeriods, usesCycleEditor, isTimeEditingLocked, session?.id, initialStartIso, initialEndIso]);

  const handleDateChange = (newDate: string) => {
    setDateValue(newDate);
    if (!newDate) return;
    const oldStart = new Date(startValue);
    const oldEnd = new Date(endValue);
    if (Number.isNaN(oldStart.getTime()) || Number.isNaN(oldEnd.getTime())) return;
    const durationMs = oldEnd.getTime() - oldStart.getTime();
    const [y, m, d] = newDate.split("-").map(Number);
    const movedStart = new Date(
      y,
      m - 1,
      d,
      oldStart.getHours(),
      oldStart.getMinutes(),
      oldStart.getSeconds()
    );
    const movedEnd = new Date(movedStart.getTime() + durationMs);
    setStartValue(toLocalDateTimeInput(movedStart.toISOString()));
    setEndValue(toLocalDateTimeInput(movedEnd.toISOString()));
  };

  const handleApplySuggestion = () => {
    if (!availability?.suggestedInterval) return;
    setStartValue(toLocalDateTimeInput(availability.suggestedInterval.start));
    setEndValue(toLocalDateTimeInput(availability.suggestedInterval.end));
    setDateValue(toLocalDateInput(availability.suggestedInterval.start));
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (isTimeEditingLocked) return;
    setErrorMessage(null);
    setSaving(true);
    try {
      if (session) {
        if (usesCycleEditor) {
          await window.worklog.sessions.update(session.id, {
            startTime: cyclePeriods[0]?.start ?? session.startTime,
            endTime: cyclePeriods[cyclePeriods.length - 1]?.end ?? session.endTime ?? session.startTime,
            note,
            workPeriods: cyclePeriods,
            expectedWorkPeriods: sourcePeriods,
            expectedStatus: session.status
          });
        } else {
          const sIso = parseLocalInputToIso(startValue);
          const eIso = parseLocalInputToIso(endValue);
          if (!sIso || !eIso) {
            throw new Error("Informe datas válidas para início e fim.");
          }
          await window.worklog.sessions.update(session.id, {
            startTime: sIso,
            endTime: eIso,
            note,
            expectedWorkPeriods: sourcePeriods,
            expectedStatus: session.status
          });
        }
      } else {
        const sIso = parseLocalInputToIso(startValue);
        const eIso = parseLocalInputToIso(endValue);
        if (!sIso || !eIso) {
          throw new Error("Informe datas válidas para início e fim.");
        }
        await window.worklog.sessions.addManual({
          projectId: project.id,
          startTime: sIso,
          endTime: eIso,
          note
        });
      }
      onSaved();
      onClose();
    } catch (err) {
      setErrorMessage(err instanceof Error ? err.message : String(err));
    } finally {
      setSaving(false);
    }
  };

  return (
    <div className="modal-backdrop" onClick={onClose}>
      <div className="modal-card" onClick={(e) => e.stopPropagation()}>
        <div className="modal-header">
          <h3>{isEditing ? "Editar Sessão" : "Nova Sessão"}</h3>
          <button type="button" className="btn btn-icon" onClick={onClose} aria-label="Fechar">
            <X size={15} />
          </button>
        </div>

        <form onSubmit={handleSubmit}>
          <div className="modal-body">
            {isTimeEditingLocked ? (
              <>
                <div className="field-group">
                  <label className="field-label">Ciclos</label>
                  <div className="session-cycles-box" style={{ marginLeft: 0 }}>
                    {sourcePeriods.map((period, index) => (
                      <div key={index} className="cycle-item">
                        <strong>Ciclo {index + 1}</strong>
                        <div className="cycle-kv">
                          <span className="muted">Início</span>
                          <span className="mono">{formatDateTimeSeconds(period.start)}</span>
                        </div>
                        <div className="cycle-kv">
                          <span className="muted">Fim</span>
                          <span className={period.end ? "mono" : "muted"}>
                            {period.end ? formatDateTimeSeconds(period.end) : "Em andamento"}
                          </span>
                        </div>
                      </div>
                    ))}
                  </div>
                </div>
                <div className="small muted">
                  Pause ou encerre o timer antes de editar esta sessão.
                </div>
              </>
            ) : usesCycleEditor ? (
              <>
                {cyclePeriods.map((period, index) => (
                  <div key={index} className="card" style={{ padding: 12 }}>
                    <div className="field-label" style={{ marginBottom: 8 }}>
                      Ciclo {index + 1}
                    </div>
                    <div className="two-col-grid" style={{ marginBottom: 8 }}>
                      <div className="field-group">
                        <label className="field-label">Início</label>
                        <input
                          className="input"
                          type="datetime-local"
                          step={1}
                          value={toLocalDateTimeInput(period.start)}
                          onChange={(e) => {
                            const iso = parseLocalInputToIso(e.target.value);
                            if (!iso) return;
                            setCyclePeriods((prev) =>
                              prev.map((item, idx) =>
                                idx === index ? { ...item, start: iso } : item
                              )
                            );
                          }}
                        />
                      </div>
                      <div className="field-group">
                        <label className="field-label">Fim</label>
                        {period.end ? (
                          <input
                            className="input"
                            type="datetime-local"
                            step={1}
                            value={toLocalDateTimeInput(period.end)}
                            onChange={(e) => {
                              const iso = parseLocalInputToIso(e.target.value);
                              if (!iso) return;
                              setCyclePeriods((prev) =>
                                prev.map((item, idx) =>
                                  idx === index ? { ...item, end: iso } : item
                                )
                              );
                            }}
                          />
                        ) : (
                          <span className="muted small">Em andamento</span>
                        )}
                      </div>
                    </div>
                    {period.end && (
                      <div className="small muted">
                        Duração:{" "}
                        <span className="mono">
                          {formatClock(
                            Math.max(0, (Date.parse(period.end) - Date.parse(period.start)) / 1000),
                            true
                          )}
                        </span>
                      </div>
                    )}
                  </div>
                ))}

                <div className="kv-row">
                  <span className="field-label">Tempo trabalhado</span>
                  <span className="mono" style={{ fontWeight: 600 }}>
                    {formatClock(cyclesTotal, true)}
                  </span>
                </div>
                <div className="small muted">As pausas entre os ciclos não entram no total.</div>
                {availability?.cycleProblem && (
                  <div className="alert-banner alert-error">{availability.cycleProblem}</div>
                )}
              </>
            ) : (
              <>
                <div className="field-group">
                  <label className="field-label">Data</label>
                  <input
                    className="input"
                    type="date"
                    value={dateValue}
                    onChange={(e) => handleDateChange(e.target.value)}
                  />
                </div>
                <div className="two-col-grid" style={{ marginBottom: 0 }}>
                  <div className="field-group">
                    <label className="field-label">Início</label>
                    <input
                      className="input"
                      type="datetime-local"
                      step={1}
                      value={startValue}
                      onChange={(e) => {
                        setStartValue(e.target.value);
                        const iso = parseLocalInputToIso(e.target.value);
                        if (iso) setDateValue(toLocalDateInput(iso));
                      }}
                    />
                  </div>
                  <div className="field-group">
                    <label className="field-label">Fim</label>
                    <input
                      className="input"
                      type="datetime-local"
                      step={1}
                      value={endValue}
                      onChange={(e) => setEndValue(e.target.value)}
                    />
                  </div>
                </div>
              </>
            )}

            {availability && availability.conflicts.length > 0 && !usesCycleEditor && (
              <div className="card" style={{ padding: 12, background: "var(--bg-subtle)" }}>
                <div className="field-label" style={{ marginBottom: 6 }}>
                  Conflitos de horário
                </div>
                <p className="small" style={{ margin: "0 0 8px" }}>
                  O período coincide com as sessões abaixo. Escolha outro horário antes de salvar.
                </p>
                {availability.conflicts.map((conflict) => (
                  <div key={conflict.sessionId} style={{ marginBottom: 6 }}>
                    <div style={{ fontWeight: 600, fontSize: 13 }}>{conflict.projectName}</div>
                    {conflict.intervals.map((iv, idx) => (
                      <div key={idx} className="small muted">
                        {formatDateTimeShort(iv.start, timeFormat)} –{" "}
                        {iv.end
                          ? formatDateTimeShort(iv.end, timeFormat)
                          : "até encerrar o timer (em execução)"}
                      </div>
                    ))}
                  </div>
                ))}
                {availability.suggestedInterval ? (
                  <div style={{ marginTop: 8, display: "flex", flexDirection: "column", gap: 6 }}>
                    <div style={{ fontWeight: 600, fontSize: 12.5 }}>
                      Horário disponível mais próximo
                    </div>
                    <div className="small">
                      {formatDateTimeShort(availability.suggestedInterval.start, timeFormat)} –{" "}
                      {formatDateTimeShort(availability.suggestedInterval.end, timeFormat)}
                    </div>
                    <div>
                      <button
                        type="button"
                        className="btn btn-sm"
                        onClick={handleApplySuggestion}
                      >
                        Usar horário sugerido
                      </button>
                    </div>
                  </div>
                ) : (
                  <div className="small muted" style={{ marginTop: 6 }}>
                    Não há horário livre com essa duração no mesmo dia do início. Altere a data ou
                    a duração.
                  </div>
                )}
              </div>
            )}

            {availabilityError && (
              <div className="alert-banner alert-error">{availabilityError}</div>
            )}

            <div className="field-group">
              <label className="field-label">Observação</label>
              <textarea
                className="textarea"
                value={note}
                onChange={(e) => setNote(e.target.value)}
              />
            </div>

            {errorMessage && <div className="alert-banner alert-error">{errorMessage}</div>}
          </div>

          <div className="modal-footer">
            <button type="button" className="btn" onClick={onClose}>
              Cancelar
            </button>
            <button
              type="submit"
              className="btn btn-primary"
              disabled={saving || isTimeEditingLocked}
            >
              Salvar
            </button>
          </div>
        </form>
      </div>
    </div>
  );
};
