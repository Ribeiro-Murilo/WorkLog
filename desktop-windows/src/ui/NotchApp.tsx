import React, { useEffect, useMemo, useRef, useState } from "react";
import {
  AlertCircle,
  ArrowUpRight,
  Monitor,
  MoreHorizontal,
  Pause,
  Pin,
  PinOff,
  Play,
  Power,
  Search,
  Settings,
  Square,
  Star,
  XCircle
} from "lucide-react";
import { formatClock, formatCompactTimer, projectColorHex } from "../shared/format";
import { WINDOWS_NOTCH_METRICS, buildNotchSvgPath } from "../shared/notchGeometry";
import { getElapsedDurationSeconds } from "../shared/periods";
import type { AppSnapshot, ProjectWithStats } from "../shared/types";
import "../styles/notch.css";

export const NotchApp: React.FC = () => {
  const [snapshot, setSnapshot] = useState<AppSnapshot | null>(null);
  const [query, setQuery] = useState("");
  const [searchFocused, setSearchFocused] = useState(false);
  const [menuOpen, setMenuOpen] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const [expandedHeight, setExpandedHeight] = useState(320);
  const [nowMs, setNowMs] = useState(() => Date.now());

  const contentRef = useRef<HTMLDivElement | null>(null);
  const searchInputRef = useRef<HTMLInputElement | null>(null);

  useEffect(() => {
    let active = true;
    void window.worklog.getSnapshot().then((data) => {
      if (active) setSnapshot(data);
    });
    const unsubscribe = window.worklog.onSnapshot((data) => {
      if (active) {
        setSnapshot(data);
        setNowMs(Date.now());
      }
    });
    return () => {
      active = false;
      unsubscribe();
    };
  }, []);

  // Atualização local suave do cronômetro enquanto houver sessão em execução
  useEffect(() => {
    if (!snapshot?.timer.isRunning) return;
    const id = window.setInterval(() => setNowMs(Date.now()), 250);
    return () => window.clearInterval(id);
  }, [snapshot?.timer.isRunning]);

  // Mede a altura real do painel expandido para o controlador do Windows
  const isExpanded = snapshot?.notch.isExpanded ?? false;
  useEffect(() => {
    if (!isExpanded || !contentRef.current) return;
    const el = contentRef.current;
    const report = () => {
      const h = Math.ceil(el.getBoundingClientRect().height);
      if (h > 0) {
        setExpandedHeight(h);
        void window.worklog.notch.setExpandedHeight(h);
      }
    };
    report();
    const observer = new ResizeObserver(report);
    observer.observe(el);
    return () => observer.disconnect();
  }, [isExpanded, snapshot, query, errorMessage, menuOpen]);

  // Fecha o menu "..." ao recolher o painel
  useEffect(() => {
    if (!isExpanded && menuOpen) {
      setMenuOpen(false);
      void window.worklog.notch.setMenuOpen(false);
    }
  }, [isExpanded, menuOpen]);

  const activeSession = snapshot?.timer.activeSession ?? null;
  const activeProject = snapshot?.timer.activeProject ?? null;
  const resumableSession = snapshot?.timer.resumableSession ?? null;
  const resumableProject = snapshot?.timer.resumableProject ?? null;

  const isRunning = snapshot?.timer.isRunning ?? false;
  const displayedProject = isRunning ? activeProject : resumableProject;
  const timerState: "running" | "paused" | "idle" = isRunning
    ? "running"
    : resumableSession && resumableProject
      ? "paused"
      : "idle";

  const showSeconds = snapshot?.settings.showSeconds ?? true;
  const elapsedSeconds = useMemo(() => {
    if (isRunning && activeSession) {
      return getElapsedDurationSeconds(activeSession, nowMs);
    }
    return resumableSession?.durationSeconds ?? 0;
  }, [isRunning, activeSession, resumableSession, nowMs]);

  const compactElapsed = isRunning ? formatCompactTimer(elapsedSeconds, showSeconds) : null;
  const elapsedFormatted = formatClock(elapsedSeconds, showSeconds);
  const todayTotalFormatted = formatClock(snapshot?.timer.todayTotalSeconds ?? 0, false);

  const visibleProjects: ProjectWithStats[] = useMemo(() => {
    if (!snapshot) return [];
    const available = snapshot.projects.filter(
      (p) => !p.isArchived && p.id !== activeProject?.id
    );
    const trimmed = query.trim().toLocaleLowerCase("pt-BR");
    if (trimmed) {
      return available.filter(
        (p) =>
          p.name.toLocaleLowerCase("pt-BR").includes(trimmed) ||
          p.client.toLocaleLowerCase("pt-BR").includes(trimmed)
      );
    }
    const byId = new Map(available.map((p) => [p.id, p]));
    const recentIds = snapshot.sessions
      .slice(0, 50)
      .map((s) => s.projectId)
      .filter((id): id is string => Boolean(id));
    const preferred = [
      ...available.filter((p) => p.isFavorite),
      ...recentIds.map((id) => byId.get(id)).filter((p): p is ProjectWithStats => Boolean(p))
    ];
    const seen = new Set<string>();
    const unique = preferred.filter((p) => {
      if (seen.has(p.id)) return false;
      seen.add(p.id);
      return true;
    });
    return unique.length > 0 ? unique : available;
  }, [snapshot, activeProject?.id, query]);

  const runAction = async (fn: () => Promise<void>) => {
    try {
      setErrorMessage(null);
      await fn();
    } catch (err) {
      setErrorMessage(err instanceof Error ? err.message : String(err));
    }
  };

  if (!snapshot) {
    return null;
  }

  if (!isExpanded) {
    const width = isRunning
      ? WINDOWS_NOTCH_METRICS.collapsedRunningTotalWidth
      : WINDOWS_NOTCH_METRICS.collapsedIdleTotalWidth;
    const height = isRunning
      ? WINDOWS_NOTCH_METRICS.collapsedRunningHeight
      : WINDOWS_NOTCH_METRICS.collapsedIdleHeight;
    const bottomRadius = isRunning
      ? WINDOWS_NOTCH_METRICS.collapsedRunningBottomRadius
      : WINDOWS_NOTCH_METRICS.collapsedIdleBottomRadius;
    const pathD = buildNotchSvgPath(
      width,
      height,
      bottomRadius,
      WINDOWS_NOTCH_METRICS.collapsedShoulderRadius
    );
    const dotColor = snapshot.notch.activeProjectColor;

    return (
      <div className="notch-root">
        <div
          className="notch-collapsed-wrapper"
          style={{ width, height }}
          onClick={() => void window.worklog.notch.expand()}
          title="WorkLog — passe o mouse ou clique para expandir"
        >
          <svg className="notch-svg-bg" width={width} height={height} viewBox={`0 0 ${width} ${height}`}>
            <path d={pathD} fill="#000000" />
          </svg>
          <div className="notch-collapsed-inner">
            {isRunning && compactElapsed ? (
              <>
                <span
                  className="notch-collapsed-running-dot"
                  style={{ backgroundColor: dotColor ?? "#38CCCF" }}
                />
                <span className="notch-collapsed-time">{compactElapsed}</span>
              </>
            ) : (
              <span
                className="notch-collapsed-dot"
                style={{
                  backgroundColor: dotColor ?? "rgba(255, 255, 255, 0.6)",
                  opacity: dotColor ? 0.8 : 1
                }}
              />
            )}
          </div>
        </div>
      </div>
    );
  }

  const expandedWidth = WINDOWS_NOTCH_METRICS.expandedTotalWidth;
  const expandedPathD = buildNotchSvgPath(
    expandedWidth,
    expandedHeight,
    WINDOWS_NOTCH_METRICS.expandedBottomRadius,
    WINDOWS_NOTCH_METRICS.expandedShoulderRadius
  );
  const isPinned = snapshot.notch.isPinned;

  return (
    <div className="notch-root">
      <div className="notch-expanded-shell" style={{ width: expandedWidth }}>
        <svg
          className="notch-svg-bg"
          width={expandedWidth}
          height={expandedHeight}
          viewBox={`0 0 ${expandedWidth} ${expandedHeight}`}
        >
          <path d={expandedPathD} fill="#000000" />
        </svg>

        <div className="notch-expanded-content" ref={contentRef}>
          <div className="notch-header">
            <span className="notch-title">WorkLog</span>
            <button
              type="button"
              className={`notch-pin-btn ${isPinned ? "pinned" : ""}`}
              title={isPinned ? "Desafixar painel" : "Manter painel aberto"}
              aria-label={isPinned ? "Desafixar painel" : "Fixar painel aberto"}
              onClick={() => void window.worklog.notch.setPinned(!isPinned)}
            >
              {isPinned ? <Pin size={13} /> : <PinOff size={13} />}
            </button>
          </div>

          <div className="notch-rule" />

          {displayedProject ? (
            <div className="notch-timer-block">
              <div className="notch-section-label">
                {timerState === "running" ? "EM ANDAMENTO" : "PAUSADO"}
              </div>
              <div className="notch-project-meta">
                <span
                  className="notch-project-dot"
                  style={{ backgroundColor: projectColorHex(displayedProject.id) }}
                />
                <div className="notch-project-copy">
                  <div className="notch-project-name" title={displayedProject.name}>
                    {displayedProject.name}
                  </div>
                  {displayedProject.client && (
                    <div className="notch-project-client" title={displayedProject.client}>
                      {displayedProject.client}
                    </div>
                  )}
                </div>
              </div>

              <div className="notch-clock">{elapsedFormatted}</div>

              {timerState === "running" ? (
                <div className="notch-actions-row">
                  <button
                    type="button"
                    className="notch-btn notch-btn-prominent"
                    onClick={() => void runAction(() => window.worklog.timer.pause())}
                  >
                    <Pause size={13} fill="currentColor" />
                    Pausar
                  </button>
                  <button
                    type="button"
                    className="notch-btn notch-btn-secondary"
                    onClick={() => void runAction(() => window.worklog.timer.stop())}
                  >
                    <Square size={12} fill="currentColor" />
                    Encerrar
                  </button>
                </div>
              ) : (
                <div className="notch-actions-row">
                  <button
                    type="button"
                    className="notch-btn notch-btn-prominent"
                    onClick={() => void runAction(() => window.worklog.timer.resume(null))}
                  >
                    <Play size={13} fill="currentColor" />
                    Retomar
                  </button>
                </div>
              )}
            </div>
          ) : (
            <div className="notch-idle-block">
              <div className="notch-idle-title">Pronto para começar</div>
              <div className="notch-idle-desc">
                Escolha um projeto para registrar seu tempo.
              </div>
            </div>
          )}

          {errorMessage && (
            <div className="notch-inline-error">
              <AlertCircle size={13} style={{ flexShrink: 0, marginTop: 1 }} />
              <span>{errorMessage}</span>
            </div>
          )}

          <div className="notch-rule" />

          <div className={`notch-search ${searchFocused ? "focused" : ""}`}>
            <Search size={13} className="notch-search-icon" />
            <input
              ref={searchInputRef}
              type="text"
              className="notch-search-input"
              placeholder="Buscar projeto…"
              value={query}
              aria-label="Buscar projeto por nome ou cliente"
              onChange={(e) => setQuery(e.target.value)}
              onFocus={() => {
                setSearchFocused(true);
                void window.worklog.notch.setEditing(true);
              }}
              onBlur={() => {
                setSearchFocused(false);
                void window.worklog.notch.setEditing(false);
              }}
              onKeyDown={(e) => {
                if (e.key === "Escape") {
                  if (query) {
                    setQuery("");
                  } else {
                    searchInputRef.current?.blur();
                  }
                }
              }}
            />
            {query && (
              <button
                type="button"
                className="notch-search-clear"
                aria-label="Limpar busca"
                onClick={() => setQuery("")}
              >
                <XCircle size={13} />
              </button>
            )}
          </div>

          <div className="notch-list-section">
            <div className="notch-section-label">
              {query.trim() ? "RESULTADOS" : "TROCAR PROJETO"}
            </div>
            {visibleProjects.length === 0 ? (
              <div className="notch-empty-list">
                {query.trim()
                  ? "Nenhum projeto encontrado."
                  : "Seus projetos aparecerão aqui."}
              </div>
            ) : (
              <div className="notch-project-scroll">
                {visibleProjects.map((project, index) => (
                  <React.Fragment key={project.id}>
                    <button
                      type="button"
                      className="notch-project-row"
                      title={
                        project.client
                          ? `${project.name} — ${project.client}`
                          : project.name
                      }
                      onClick={() =>
                        void runAction(() => window.worklog.timer.start(project.id))
                      }
                    >
                      <span
                        className="notch-row-dot"
                        style={{ backgroundColor: projectColorHex(project.id) }}
                      />
                      <span className="notch-row-text">
                        <span className="notch-row-title-line">
                          <span className="notch-row-name">{project.name}</span>
                          {project.isFavorite && (
                            <Star size={10} fill="currentColor" className="notch-row-star" />
                          )}
                        </span>
                        {project.client && (
                          <span className="notch-row-client">{project.client}</span>
                        )}
                      </span>
                      <span className="notch-row-play">
                        <Play size={10} fill="currentColor" />
                      </span>
                    </button>
                    {index < visibleProjects.length - 1 && (
                      <div className="notch-row-divider" />
                    )}
                  </React.Fragment>
                ))}
              </div>
            )}
          </div>

          <div className="notch-rule" />

          <div className="notch-today-row">
            <span className="notch-today-label">Registrado hoje</span>
            <span className="notch-today-value">{todayTotalFormatted}</span>
          </div>

          <div className="notch-rule" />

          <div className="notch-footer">
            <button
              type="button"
              className="notch-footer-link"
              onClick={() => {
                void window.worklog.notch.collapse();
                void window.worklog.app.openDashboard("summary");
              }}
            >
              <ArrowUpRight size={13} />
              Abrir Dashboard
            </button>

            <span className="notch-footer-spacer" />

            <button
              type="button"
              className="notch-footer-icon-btn"
              title="Configurações"
              aria-label="Configurações"
              onClick={() => {
                void window.worklog.notch.collapse();
                void window.worklog.app.openDashboard("settings");
              }}
            >
              <Settings size={14} />
            </button>

            <button
              type="button"
              className="notch-footer-icon-btn"
              title="Mais opções"
              aria-label="Mais opções"
              onClick={() => {
                const next = !menuOpen;
                setMenuOpen(next);
                void window.worklog.notch.setMenuOpen(next);
              }}
            >
              <MoreHorizontal size={15} />
            </button>

            {menuOpen && (
              <div className="notch-menu-popover">
                <button
                  type="button"
                  className="notch-menu-item"
                  onClick={() => {
                    setMenuOpen(false);
                    void window.worklog.notch.setMenuOpen(false);
                    void window.worklog.settings.save({ displayMode: "menuBar" });
                  }}
                >
                  <Monitor size={13} />
                  Usar somente na bandeja
                </button>
                <button
                  type="button"
                  className="notch-menu-item danger"
                  onClick={() => {
                    setMenuOpen(false);
                    void window.worklog.notch.setMenuOpen(false);
                    void window.worklog.app.quit();
                  }}
                >
                  <Power size={13} />
                  Sair do WorkLog
                </button>
              </div>
            )}
          </div>
        </div>
      </div>
    </div>
  );
};
