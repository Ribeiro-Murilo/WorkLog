import React, { useEffect, useState } from "react";
import { ChevronDown, ChevronRight } from "lucide-react";
import { formatClock, formatDateTimeSeconds, formatShortDate } from "../../shared/format";
import { SESSION_STATUS_LABELS, type SessionWithProject } from "../../shared/types";

interface SessionRowProps {
  session: SessionWithProject;
  onEditCycles?: () => void;
}

export const SessionRow: React.FC<SessionRowProps> = ({ session, onEditCycles }) => {
  const [expanded, setExpanded] = useState(false);
  const [nowMs, setNowMs] = useState(() => Date.now());

  const hasOpenPeriod =
    expanded && session.normalizedPeriods.some((p) => p.end === null);

  useEffect(() => {
    if (!hasOpenPeriod) return;
    const id = window.setInterval(() => setNowMs(Date.now()), 1000);
    return () => window.clearInterval(id);
  }, [hasOpenPeriod]);

  return (
    <div className="session-row">
      <button
        type="button"
        className="session-summary-btn"
        onClick={() => setExpanded((prev) => !prev)}
      >
        <span style={{ display: "flex", alignItems: "center", gap: 8, minWidth: 0 }}>
          {expanded ? <ChevronDown size={14} /> : <ChevronRight size={14} />}
          <span>
            <span style={{ fontWeight: 500, display: "block" }}>{session.projectName}</span>
            <span className="muted small">{formatShortDate(session.date)}</span>
          </span>
        </span>

        <span style={{ textAlign: "right", flexShrink: 0 }}>
          <span className="tabular" style={{ fontWeight: 500, display: "block" }}>
            {formatClock(session.durationSeconds, false)}
          </span>
          <span className="muted small">{SESSION_STATUS_LABELS[session.status]}</span>
        </span>
      </button>

      {expanded && (
        <div className="session-cycles-box">
          {session.normalizedPeriods.map((period, index) => {
            const startMs = Date.parse(period.start);
            const endMs = period.end ? Date.parse(period.end) : nowMs;
            const duration = Math.max(0, (endMs - startMs) / 1000);

            return (
              <React.Fragment key={`${session.id}-cycle-${index}`}>
                <div className="cycle-item">
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
                  <div className="cycle-kv">
                    <span className="muted">Duração</span>
                    <span className="mono">{formatClock(duration, true)}</span>
                  </div>
                </div>
                {index < session.normalizedPeriods.length - 1 && (
                  <div className="list-divider" />
                )}
              </React.Fragment>
            );
          })}

          {session.note && (
            <div className="small muted">Observação: {session.note}</div>
          )}

          {onEditCycles && session.status !== "running" && (
            <div>
              <button type="button" className="btn btn-sm" onClick={onEditCycles}>
                Editar ciclos
              </button>
            </div>
          )}
        </div>
      )}
    </div>
  );
};
