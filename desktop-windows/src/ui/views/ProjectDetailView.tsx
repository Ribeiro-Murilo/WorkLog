import React, { useEffect, useMemo, useState } from "react";
import {
  ArrowLeft,
  Banknote,
  Briefcase,
  CircleDollarSign,
  Clock,
  Pause,
  Pencil,
  Play,
  PlusCircle,
  Square,
  Trash2,
  User
} from "lucide-react";
import {
  formatClock,
  formatCurrencyBRL,
  formatDateTimeShort,
  projectColorHex
} from "../../shared/format";
import { getElapsedDurationSeconds, getLatestActivityMs } from "../../shared/periods";
import {
  PROJECT_CATEGORY_LABELS,
  PROJECT_STATUS_LABELS,
  type AppSnapshot,
  type Comment,
  type ProjectWithStats,
  type SessionWithProject
} from "../../shared/types";
import { SessionRow } from "../components/SessionRow";
import { ConfirmModal } from "../modals/ConfirmModal";
import { ProjectFormModal } from "../modals/ProjectFormModal";
import { SessionFormModal } from "../modals/SessionFormModal";

interface ProjectDetailViewProps {
  project: ProjectWithStats;
  snapshot: AppSnapshot;
  onBack: () => void;
}

export const ProjectDetailView: React.FC<ProjectDetailViewProps> = ({
  project,
  snapshot,
  onBack
}) => {
  const [showingEditForm, setShowingEditForm] = useState(false);
  const [showingNewSession, setShowingNewSession] = useState(false);
  const [editingSession, setEditingSession] = useState<SessionWithProject | null>(null);
  const [deletingSession, setDeletingSession] = useState<SessionWithProject | null>(null);
  const [deletingComment, setDeletingComment] = useState<Comment | null>(null);
  const [commentText, setCommentText] = useState("");
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const [nowMs, setNowMs] = useState(() => Date.now());

  const projectSessions = useMemo(
    () => snapshot.sessions.filter((s) => s.projectId === project.id),
    [snapshot.sessions, project.id]
  );
  const comments = snapshot.commentsByProject[project.id] ?? [];

  const isRunningThisProject =
    snapshot.timer.isRunning && snapshot.timer.activeProject?.id === project.id;

  useEffect(() => {
    if (!isRunningThisProject) return;
    const id = window.setInterval(() => setNowMs(Date.now()), 250);
    return () => window.clearInterval(id);
  }, [isRunningThisProject]);

  const elapsedSeconds = useMemo(() => {
    if (!isRunningThisProject || !snapshot.timer.activeSession) return 0;
    return getElapsedDurationSeconds(snapshot.timer.activeSession, nowMs);
  }, [isRunningThisProject, snapshot.timer.activeSession, nowMs]);

  const canResume = useMemo(() => {
    if (project.isArchived || projectSessions.length === 0) return false;
    const latest = [...projectSessions].sort(
      (a, b) => getLatestActivityMs(b) - getLatestActivityMs(a)
    )[0];
    return Boolean(latest && latest.status === "paused" && latest.endTime !== null);
  }, [project.isArchived, projectSessions]);

  const runAction = async (fn: () => Promise<void>) => {
    try {
      setErrorMessage(null);
      await fn();
    } catch (err) {
      setErrorMessage(err instanceof Error ? err.message : String(err));
    }
  };

  const handleAddComment = async () => {
    const trimmed = commentText.trim();
    if (!trimmed) return;
    await runAction(async () => {
      await window.worklog.comments.add(project.id, trimmed);
      setCommentText("");
    });
  };

  return (
    <div>
      <div className="page-header">
        <div className="page-title-row">
          <button type="button" className="btn btn-sm" onClick={onBack}>
            <ArrowLeft size={14} /> Projetos
          </button>
          <span
            className="project-dot"
            style={{ backgroundColor: projectColorHex(project.id), width: 12, height: 12 }}
          />
          <h1 className="page-title">{project.name}</h1>
        </div>
        <button type="button" className="btn" onClick={() => setShowingEditForm(true)}>
          <Pencil size={14} /> Editar
        </button>
      </div>

      {errorMessage && (
        <div className="alert-banner alert-error" style={{ marginBottom: 14 }}>
          {errorMessage}
        </div>
      )}

      <div className="card" style={{ marginBottom: 16 }}>
        <div
          className="small muted"
          style={{ display: "flex", alignItems: "center", gap: 8, marginBottom: 6 }}
        >
          <span>{PROJECT_STATUS_LABELS[project.status]}</span>
          <span>•</span>
          <span style={{ display: "inline-flex", alignItems: "center", gap: 4 }}>
            {project.category === "work" ? <Briefcase size={13} /> : <User size={13} />}
            {PROJECT_CATEGORY_LABELS[project.category]}
          </span>
        </div>

        <div style={{ fontSize: 17, fontWeight: 600, marginBottom: 4 }}>{project.client}</div>

        {project.descriptionText && (
          <p className="muted" style={{ margin: "6px 0 10px", fontSize: 13.5 }}>
            {project.descriptionText}
          </p>
        )}

        {project.tags.length > 0 && (
          <div style={{ display: "flex", gap: 6, flexWrap: "wrap", marginBottom: 12 }}>
            {project.tags.map((tag) => (
              <span key={tag} className="badge">
                {tag}
              </span>
            ))}
          </div>
        )}

        <div className="summary-grid" style={{ marginBottom: 0, marginTop: 10 }}>
          <div className="card" style={{ background: "var(--bg-subtle)" }}>
            <div className="summary-card-label">
              <Banknote size={14} /> Valor por dia
            </div>
            <div className="summary-card-value tabular">
              {formatCurrencyBRL(project.dailyRate)}
            </div>
          </div>
          <div className="card" style={{ background: "var(--bg-subtle)" }}>
            <div className="summary-card-label">
              <Clock size={14} /> Tempo acumulado
            </div>
            <div className="summary-card-value tabular">
              {formatClock(project.totalWorkedSeconds, false)}
            </div>
          </div>
          <div className="card" style={{ background: "var(--bg-subtle)" }}>
            <div className="summary-card-label">
              <CircleDollarSign size={14} /> Valor acumulado
            </div>
            <div className="summary-card-value tabular">
              {formatCurrencyBRL(project.totalValue)}
            </div>
          </div>
        </div>
      </div>

      <div className="card" style={{ marginBottom: 16 }}>
        <h2 className="section-title">Timer</h2>
        {isRunningThisProject ? (
          <div>
            <div className="mono" style={{ fontSize: 32, fontWeight: 600, marginBottom: 12 }}>
              {formatClock(elapsedSeconds, true)}
            </div>
            <div className="toolbar-actions">
              <button
                type="button"
                className="btn"
                onClick={() => void runAction(() => window.worklog.timer.pause())}
              >
                <Pause size={14} /> Pausar
              </button>
              <button
                type="button"
                className="btn btn-danger"
                onClick={() => void runAction(() => window.worklog.timer.stop())}
              >
                <Square size={14} /> Encerrar
              </button>
            </div>
          </div>
        ) : (
          <div className="toolbar-actions">
            {canResume ? (
              <button
                type="button"
                className="btn btn-primary"
                onClick={() =>
                  void runAction(() => window.worklog.timer.resume(project.id))
                }
              >
                <Play size={14} /> Retomar
              </button>
            ) : (
              <button
                type="button"
                className="btn btn-primary"
                disabled={project.isArchived}
                onClick={() =>
                  void runAction(() => window.worklog.timer.start(project.id))
                }
              >
                <Play size={14} /> Iniciar
              </button>
            )}
            <button
              type="button"
              className="btn"
              onClick={() => setShowingNewSession(true)}
            >
              <PlusCircle size={14} /> Adicionar sessão manualmente
            </button>
          </div>
        )}
      </div>

      <div className="card" style={{ marginBottom: 16 }}>
        <h2 className="section-title">Comentários</h2>
        <div style={{ display: "flex", gap: 8, marginBottom: 12 }}>
          <input
            className="input"
            style={{ flex: 1 }}
            type="text"
            placeholder="Adicionar um comentário…"
            value={commentText}
            onChange={(e) => setCommentText(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === "Enter") {
                e.preventDefault();
                void handleAddComment();
              }
            }}
          />
          <button
            type="button"
            className="btn"
            disabled={!commentText.trim()}
            onClick={() => void handleAddComment()}
          >
            <PlusCircle size={14} /> Adicionar
          </button>
        </div>

        {comments.length === 0 ? (
          <div className="small muted">Nenhum comentário ainda.</div>
        ) : (
          <div className="list-stack">
            {comments.map((comment, idx) => (
              <React.Fragment key={comment.id}>
                <div
                  style={{
                    display: "flex",
                    alignItems: "flex-start",
                    justifyContent: "space-between",
                    gap: 12,
                    padding: "8px 0"
                  }}
                >
                  <div>
                    <div className="small muted" style={{ marginBottom: 2 }}>
                      <strong style={{ color: "var(--text-primary)" }}>{comment.author}</strong> •{" "}
                      {formatDateTimeShort(comment.createdAt, snapshot.settings.timeFormat)}
                    </div>
                    <div style={{ fontSize: 13.5, whiteSpace: "pre-wrap" }}>{comment.text}</div>
                  </div>
                  <button
                    type="button"
                    className="btn btn-icon btn-danger"
                    title="Excluir comentário"
                    onClick={() => setDeletingComment(comment)}
                  >
                    <Trash2 size={13} />
                  </button>
                </div>
                {idx < comments.length - 1 && <div className="list-divider" />}
              </React.Fragment>
            ))}
          </div>
        )}
      </div>

      <div className="card">
        <h2 className="section-title">Sessões</h2>
        {projectSessions.length === 0 ? (
          <div className="small muted">Nenhuma sessão registrada ainda.</div>
        ) : (
          <div className="list-stack">
            {projectSessions.map((session, idx) => (
              <React.Fragment key={session.id}>
                <div style={{ display: "flex", alignItems: "flex-start", gap: 8 }}>
                  <div style={{ flex: 1 }}>
                    <SessionRow
                      session={session}
                      onEditCycles={() => setEditingSession(session)}
                    />
                  </div>
                  <div style={{ display: "flex", gap: 4, paddingTop: 10 }}>
                    <button
                      type="button"
                      className="btn btn-icon"
                      title="Editar"
                      onClick={() => setEditingSession(session)}
                    >
                      <Pencil size={13} />
                    </button>
                    <button
                      type="button"
                      className="btn btn-icon btn-danger"
                      title="Excluir"
                      onClick={() => setDeletingSession(session)}
                    >
                      <Trash2 size={13} />
                    </button>
                  </div>
                </div>
                {idx < projectSessions.length - 1 && <div className="list-divider" />}
              </React.Fragment>
            ))}
          </div>
        )}
      </div>

      {showingEditForm && (
        <ProjectFormModal
          project={project}
          onClose={() => setShowingEditForm(false)}
          onSaved={() => setErrorMessage(null)}
        />
      )}

      {showingNewSession && (
        <SessionFormModal
          project={project}
          session={null}
          timeFormat={snapshot.settings.timeFormat}
          onClose={() => setShowingNewSession(false)}
          onSaved={() => setErrorMessage(null)}
        />
      )}

      {editingSession && (
        <SessionFormModal
          project={project}
          session={editingSession}
          timeFormat={snapshot.settings.timeFormat}
          onClose={() => setEditingSession(null)}
          onSaved={() => setErrorMessage(null)}
        />
      )}

      {deletingSession && (
        <ConfirmModal
          title="Excluir sessão?"
          message="Esta sessão será removida permanentemente."
          onCancel={() => setDeletingSession(null)}
          onConfirm={() => {
            const id = deletingSession.id;
            setDeletingSession(null);
            void runAction(() => window.worklog.sessions.delete(id));
          }}
        />
      )}

      {deletingComment && (
        <ConfirmModal
          title="Excluir comentário?"
          message="Este comentário será removido permanentemente."
          onCancel={() => setDeletingComment(null)}
          onConfirm={() => {
            const id = deletingComment.id;
            setDeletingComment(null);
            void runAction(() => window.worklog.comments.delete(id));
          }}
        />
      )}
    </div>
  );
};
