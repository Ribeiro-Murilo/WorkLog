import React, { useEffect, useMemo, useState } from "react";
import {
  BarChart3,
  FileText,
  Folder,
  LayoutGrid,
  Pause,
  Play,
  Settings,
  Square
} from "lucide-react";
import { formatClock, projectColorHex } from "../shared/format";
import { getElapsedDurationSeconds } from "../shared/periods";
import type { AppSnapshot, DashboardSection } from "../shared/types";
import "../styles/app.css";
import { BillingView } from "./views/BillingView";
import { ProjectsView } from "./views/ProjectsView";
import { ReportsView } from "./views/ReportsView";
import { SettingsView } from "./views/SettingsView";
import { SummaryView } from "./views/SummaryView";

const NAV_ITEMS: Array<{ id: DashboardSection; label: string; icon: React.ReactNode }> = [
  { id: "summary", label: "Resumo", icon: <LayoutGrid size={16} /> },
  { id: "projects", label: "Projetos", icon: <Folder size={16} /> },
  { id: "reports", label: "Relatórios", icon: <BarChart3 size={16} /> },
  { id: "billing", label: "Faturamento", icon: <FileText size={16} /> }
];

function getInitialRouteParams(): {
  section: DashboardSection;
  focusSearch: number;
  openNewProject: number;
} {
  const params = new URLSearchParams(window.location.search);
  const rawSection = params.get("section") as DashboardSection | null;
  const valid: DashboardSection[] = ["summary", "projects", "reports", "billing", "settings"];
  return {
    section: rawSection && valid.includes(rawSection) ? rawSection : "summary",
    focusSearch: params.get("focusSearch") === "1" ? 1 : 0,
    openNewProject: params.get("openNewProject") === "1" ? 1 : 0
  };
}

export const DashboardApp: React.FC = () => {
  const initial = useMemo(() => getInitialRouteParams(), []);
  const [snapshot, setSnapshot] = useState<AppSnapshot | null>(null);
  const [section, setSection] = useState<DashboardSection>(initial.section);
  const [focusSearchTrigger, setFocusSearchTrigger] = useState(initial.focusSearch);
  const [openNewProjectTrigger, setOpenNewProjectTrigger] = useState(initial.openNewProject);
  const [nowMs, setNowMs] = useState(() => Date.now());

  const logoSrc = useMemo(() => new URL("../../assets/icon.png", import.meta.url).href, []);

  useEffect(() => {
    let active = true;
    void window.worklog.getSnapshot().then((data) => {
      if (active) setSnapshot(data);
    });
    const unsubSnap = window.worklog.onSnapshot((data) => {
      if (active) {
        setSnapshot(data);
        setNowMs(Date.now());
      }
    });
    const unsubNav = window.worklog.onNavigate((nextSection, focusSearch, openNewProject) => {
      if (!active) return;
      setSection(nextSection);
      if (focusSearch) setFocusSearchTrigger((c) => c + 1);
      if (openNewProject) setOpenNewProjectTrigger((c) => c + 1);
    });
    return () => {
      active = false;
      unsubSnap();
      unsubNav();
    };
  }, []);

  useEffect(() => {
    const theme = snapshot?.settings.theme ?? "system";
    document.documentElement.setAttribute("data-theme", theme);
  }, [snapshot?.settings.theme]);

  useEffect(() => {
    if (!snapshot?.timer.isRunning) return;
    const id = window.setInterval(() => setNowMs(Date.now()), 250);
    return () => window.clearInterval(id);
  }, [snapshot?.timer.isRunning]);

  const activeSession = snapshot?.timer.activeSession ?? null;
  const activeProject = snapshot?.timer.activeProject ?? null;
  const resumableProject = snapshot?.timer.resumableProject ?? null;
  const isRunning = snapshot?.timer.isRunning ?? false;

  const sidebarElapsed = useMemo(() => {
    if (isRunning && activeSession) {
      return getElapsedDurationSeconds(activeSession, nowMs);
    }
    return snapshot?.timer.resumableSession?.durationSeconds ?? 0;
  }, [isRunning, activeSession, snapshot?.timer.resumableSession, nowMs]);

  if (!snapshot) {
    return (
      <div
        style={{
          height: "100%",
          display: "flex",
          alignItems: "center",
          justifyContent: "center"
        }}
      >
        <span className="muted">Carregando WorkLog…</span>
      </div>
    );
  }

  return (
    <div className="app-shell">
      <aside className="sidebar">
        <div className="sidebar-brand">
          <img
            src={logoSrc}
            alt="WorkLog"
            style={{ width: 26, height: 26, borderRadius: 7 }}
          />
          <span className="sidebar-brand-title">WorkLog</span>
        </div>

        <nav className="sidebar-nav">
          {NAV_ITEMS.map((item) => (
            <button
              key={item.id}
              type="button"
              className={`nav-item ${section === item.id ? "active" : ""}`}
              onClick={() => setSection(item.id)}
            >
              {item.icon}
              <span>{item.label}</span>
            </button>
          ))}
        </nav>

        {(activeProject || resumableProject) && (
          <div className="sidebar-timer-box">
            <div
              className="sidebar-timer-project"
              title={(activeProject ?? resumableProject)!.name}
            >
              <span
                className="project-dot"
                style={{
                  backgroundColor: projectColorHex((activeProject ?? resumableProject)!.id)
                }}
              />
              <span>{(activeProject ?? resumableProject)!.name}</span>
            </div>
            <div className="mono sidebar-timer-clock">
              {formatClock(sidebarElapsed, snapshot.settings.showSeconds)}
            </div>
            <div className="sidebar-timer-actions">
              {isRunning ? (
                <>
                  <button
                    type="button"
                    className="btn btn-sm"
                    style={{ flex: 1 }}
                    onClick={() => void window.worklog.timer.pause()}
                  >
                    <Pause size={12} /> Pausar
                  </button>
                  <button
                    type="button"
                    className="btn btn-sm btn-danger"
                    onClick={() => void window.worklog.timer.stop()}
                    title="Encerrar"
                  >
                    <Square size={12} />
                  </button>
                </>
              ) : (
                <button
                  type="button"
                  className="btn btn-sm btn-primary"
                  style={{ flex: 1 }}
                  onClick={() => void window.worklog.timer.resume(null)}
                >
                  <Play size={12} /> Retomar
                </button>
              )}
            </div>
          </div>
        )}

        <button
          type="button"
          className={`nav-item ${section === "settings" ? "active" : ""}`}
          onClick={() => setSection("settings")}
        >
          <Settings size={16} />
          <span>Configurações</span>
        </button>
      </aside>

      <main className="main-area">
        {section === "summary" && <SummaryView snapshot={snapshot} logoSrc={logoSrc} />}
        {section === "projects" && (
          <ProjectsView
            snapshot={snapshot}
            focusSearchTrigger={focusSearchTrigger}
            openNewProjectTrigger={openNewProjectTrigger}
          />
        )}
        {section === "reports" && <ReportsView snapshot={snapshot} />}
        {section === "billing" && <BillingView snapshot={snapshot} />}
        {section === "settings" && <SettingsView snapshot={snapshot} logoSrc={logoSrc} />}
      </main>
    </div>
  );
};
