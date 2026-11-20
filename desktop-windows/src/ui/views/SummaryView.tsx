import React from "react";
import { Archive, Calendar, Clock, Folder, Sun } from "lucide-react";
import { formatClock } from "../../shared/format";
import { PROJECT_CATEGORY_LABELS, type AppSnapshot } from "../../shared/types";
import { SessionRow } from "../components/SessionRow";

interface SummaryViewProps {
  snapshot: AppSnapshot;
  logoSrc: string;
}

export const SummaryView: React.FC<SummaryViewProps> = ({ snapshot, logoSrc }) => {
  const { dashboard } = snapshot;

  return (
    <div>
      <div className="page-header">
        <div className="page-title-row">
          <img
            src={logoSrc}
            alt="WorkLog"
            style={{ width: 32, height: 32, borderRadius: 8 }}
          />
          <h1 className="page-title">Resumo</h1>
        </div>
      </div>

      <div className="summary-grid">
        <div className="card">
          <div className="summary-card-label">
            <Sun size={14} /> Hoje
          </div>
          <div className="summary-card-value tabular">
            {formatClock(dashboard.todayTotal, false)}
          </div>
        </div>
        <div className="card">
          <div className="summary-card-label">
            <Calendar size={14} /> Semana
          </div>
          <div className="summary-card-value tabular">
            {formatClock(dashboard.weekTotal, false)}
          </div>
        </div>
        <div className="card">
          <div className="summary-card-label">
            <Calendar size={14} /> Mês
          </div>
          <div className="summary-card-value tabular">
            {formatClock(dashboard.monthTotal, false)}
          </div>
        </div>
        <div className="card">
          <div className="summary-card-label">
            <Clock size={14} /> Tempo total
          </div>
          <div className="summary-card-value tabular">
            {formatClock(dashboard.allTimeTotal, false)}
          </div>
        </div>
        <div className="card">
          <div className="summary-card-label">
            <Folder size={14} /> Projetos ativos
          </div>
          <div className="summary-card-value tabular">{dashboard.activeProjectsCount}</div>
        </div>
        <div className="card">
          <div className="summary-card-label">
            <Archive size={14} /> Projetos arquivados
          </div>
          <div className="summary-card-value tabular">{dashboard.archivedProjectsCount}</div>
        </div>
      </div>

      <div className="two-col-grid">
        <div className="card">
          <h2 className="section-title">Últimas sessões</h2>
          {dashboard.recentSessions.length === 0 ? (
            <div className="small muted">Nenhuma sessão registrada.</div>
          ) : (
            <div className="list-stack">
              {dashboard.recentSessions.map((session, idx) => (
                <React.Fragment key={session.id}>
                  <SessionRow session={session} />
                  {idx < dashboard.recentSessions.length - 1 && (
                    <div className="list-divider" />
                  )}
                </React.Fragment>
              ))}
            </div>
          )}
        </div>

        <div className="card">
          <h2 className="section-title">Projetos mais utilizados</h2>
          {dashboard.mostUsedProjects.length === 0 ? (
            <div className="small muted">Sem dados ainda.</div>
          ) : (
            <div className="kv-list">
              {dashboard.mostUsedProjects.slice(0, 6).map((entry) => (
                <div key={entry.project.id} className="kv-row">
                  <span>{entry.project.name}</span>
                  <span className="muted tabular">{formatClock(entry.total, false)}</span>
                </div>
              ))}
            </div>
          )}
        </div>
      </div>

      <div className="two-col-grid">
        <div className="card">
          <h2 className="section-title">Tempo por categoria</h2>
          {dashboard.timeByCategory.length === 0 ? (
            <div className="small muted">Sem dados ainda.</div>
          ) : (
            <div className="kv-list">
              {dashboard.timeByCategory.slice(0, 8).map((item) => (
                <div key={item.category} className="kv-row">
                  <span>{PROJECT_CATEGORY_LABELS[item.category]}</span>
                  <span className="muted tabular">{formatClock(item.total, false)}</span>
                </div>
              ))}
            </div>
          )}
        </div>

        <div className="card">
          <h2 className="section-title">Tempo por cliente</h2>
          {dashboard.timeByClient.length === 0 ? (
            <div className="small muted">Sem dados ainda.</div>
          ) : (
            <div className="kv-list">
              {dashboard.timeByClient.slice(0, 8).map((item) => (
                <div key={item.client} className="kv-row">
                  <span>{item.client}</span>
                  <span className="muted tabular">{formatClock(item.total, false)}</span>
                </div>
              ))}
            </div>
          )}
        </div>
      </div>

      <div className="card">
        <h2 className="section-title">Tempo por projeto</h2>
        {dashboard.timeByProject.length === 0 ? (
          <div className="small muted">Sem dados ainda.</div>
        ) : (
          <div className="kv-list">
            {dashboard.timeByProject.slice(0, 8).map((item) => (
              <div key={item.project.id} className="kv-row">
                <span>{item.project.name}</span>
                <span className="muted tabular">{formatClock(item.total, false)}</span>
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  );
};
