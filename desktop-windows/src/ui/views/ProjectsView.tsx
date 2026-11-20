import React, { useEffect, useMemo, useRef, useState } from "react";
import { Archive, Briefcase, Folder, Plus, Search, Star, Trash2, User } from "lucide-react";
import { formatClock, formatCurrencyBRL, projectColorHex } from "../../shared/format";
import {
  PROJECT_CATEGORY_LABELS,
  PROJECT_SORT_LABELS,
  PROJECT_STATUS_LABELS,
  type AppSnapshot,
  type ProjectCategory,
  type ProjectSortOption,
  type ProjectStatus,
  type ProjectWithStats
} from "../../shared/types";
import { ConfirmModal } from "../modals/ConfirmModal";
import { ProjectFormModal } from "../modals/ProjectFormModal";
import { ProjectDetailView } from "./ProjectDetailView";

interface ProjectsViewProps {
  snapshot: AppSnapshot;
  focusSearchTrigger: number;
  openNewProjectTrigger: number;
}

export const ProjectsView: React.FC<ProjectsViewProps> = ({
  snapshot,
  focusSearchTrigger,
  openNewProjectTrigger
}) => {
  const [selectedProjectId, setSelectedProjectId] = useState<string | null>(null);
  const [searchQuery, setSearchQuery] = useState("");
  const [statusFilter, setStatusFilter] = useState<ProjectStatus | "">("");
  const [categoryFilter, setCategoryFilter] = useState<ProjectCategory | "">("");
  const [includeArchived, setIncludeArchived] = useState(false);
  const [sortOption, setSortOption] = useState<ProjectSortOption>("name");
  const [showingNewForm, setShowingNewForm] = useState(false);
  const [pendingDelete, setPendingDelete] = useState<ProjectWithStats | null>(null);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  const searchRef = useRef<HTMLInputElement | null>(null);

  useEffect(() => {
    if (focusSearchTrigger > 0) {
      setSelectedProjectId(null);
      window.setTimeout(() => searchRef.current?.focus(), 40);
    }
  }, [focusSearchTrigger]);

  useEffect(() => {
    if (openNewProjectTrigger > 0) {
      setShowingNewForm(true);
    }
  }, [openNewProjectTrigger]);

  const selectedProject = useMemo(
    () => snapshot.projects.find((p) => p.id === selectedProjectId) ?? null,
    [snapshot.projects, selectedProjectId]
  );

  const filteredProjects = useMemo(() => {
    const q = searchQuery.trim().toLocaleLowerCase("pt-BR");
    const list = snapshot.projects.filter((project) => {
      if (!includeArchived && project.isArchived) return false;
      if (statusFilter && project.status !== statusFilter) return false;
      if (categoryFilter && project.category !== categoryFilter) return false;
      if (q) {
        const hay =
          project.name.toLocaleLowerCase("pt-BR").includes(q) ||
          project.client.toLocaleLowerCase("pt-BR").includes(q) ||
          project.descriptionText.toLocaleLowerCase("pt-BR").includes(q);
        if (!hay) return false;
      }
      return true;
    });

    list.sort((a, b) => {
      if (sortOption === "name") return a.name.localeCompare(b.name, "pt-BR");
      if (sortOption === "client") return a.client.localeCompare(b.client, "pt-BR");
      return Date.parse(b.createdAt) - Date.parse(a.createdAt);
    });
    return list;
  }, [snapshot.projects, includeArchived, statusFilter, categoryFilter, searchQuery, sortOption]);

  if (selectedProject) {
    return (
      <ProjectDetailView
        project={selectedProject}
        snapshot={snapshot}
        onBack={() => setSelectedProjectId(null)}
      />
    );
  }

  return (
    <div>
      <div className="page-header">
        <h1 className="page-title">Projetos</h1>
        <div className="toolbar-actions">
          <button
            type="button"
            className="btn btn-primary"
            onClick={() => setShowingNewForm(true)}
          >
            <Plus size={15} />
            Novo Projeto
          </button>
        </div>
      </div>

      <div className="filters-row">
        <div className="search-box">
          <Search size={15} />
          <input
            ref={searchRef}
            className="input"
            type="text"
            placeholder="Pesquisar projetos"
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
          />
        </div>

        <select
          className="select"
          value={statusFilter}
          onChange={(e) => setStatusFilter(e.target.value as ProjectStatus | "")}
        >
          <option value="">Todos os status</option>
          {(Object.keys(PROJECT_STATUS_LABELS) as ProjectStatus[]).map((s) => (
            <option key={s} value={s}>
              {PROJECT_STATUS_LABELS[s]}
            </option>
          ))}
        </select>

        <select
          className="select"
          value={categoryFilter}
          onChange={(e) => setCategoryFilter(e.target.value as ProjectCategory | "")}
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
          value={sortOption}
          onChange={(e) => setSortOption(e.target.value as ProjectSortOption)}
        >
          {(Object.keys(PROJECT_SORT_LABELS) as ProjectSortOption[]).map((opt) => (
            <option key={opt} value={opt}>
              Ordenar: {PROJECT_SORT_LABELS[opt]}
            </option>
          ))}
        </select>

        <label className="checkbox-line">
          <input
            type="checkbox"
            checked={includeArchived}
            onChange={(e) => setIncludeArchived(e.target.checked)}
          />
          Incluir arquivados
        </label>
      </div>

      {errorMessage && (
        <div className="alert-banner alert-error" style={{ marginBottom: 14 }}>
          {errorMessage}
        </div>
      )}

      <div className="card" style={{ padding: 6 }}>
        {filteredProjects.length === 0 ? (
          <div className="empty-state">
            <Folder size={28} />
            <strong>Nenhum projeto encontrado</strong>
            <span className="small">
              Crie um novo projeto para começar a controlar o tempo.
            </span>
          </div>
        ) : (
          <div className="list-stack">
            {filteredProjects.map((project, index) => {
              const isRunning = snapshot.timer.activeProject?.id === project.id;
              return (
                <React.Fragment key={project.id}>
                  <div
                    className="project-list-item"
                    onClick={() => setSelectedProjectId(project.id)}
                  >
                    <div className="project-item-left">
                      <span
                        className="project-dot"
                        style={{ backgroundColor: projectColorHex(project.id) }}
                      />
                      {project.category === "work" ? (
                        <Briefcase size={15} className="muted" />
                      ) : (
                        <User size={15} className="muted" />
                      )}
                      <div>
                        <div className="project-item-name">
                          <span>{project.name}</span>
                          {isRunning && <span className="badge badge-success">Em execução</span>}
                          {project.isArchived && <span className="badge">Arquivado</span>}
                        </div>
                        <div className="project-item-sub">
                          {project.client} • {PROJECT_STATUS_LABELS[project.status]}
                        </div>
                      </div>
                    </div>

                    <div
                      className="project-item-right"
                      onClick={(e) => e.stopPropagation()}
                    >
                      <span className="small muted tabular" style={{ marginRight: 6 }}>
                        {formatClock(project.totalWorkedSeconds, false)} •{" "}
                        {formatCurrencyBRL(project.totalValue)}
                      </span>
                      <button
                        type="button"
                        className="btn btn-icon"
                        title={
                          project.isFavorite
                            ? "Remover dos favoritos"
                            : "Marcar como favorito"
                        }
                        onClick={() =>
                          void window.worklog.projects
                            .toggleFavorite(project.id)
                            .catch((err) => setErrorMessage(String(err)))
                        }
                      >
                        <Star
                          size={14}
                          fill={project.isFavorite ? "#eab308" : "none"}
                          color={project.isFavorite ? "#eab308" : "currentColor"}
                        />
                      </button>
                      <button
                        type="button"
                        className="btn btn-icon"
                        title={project.isArchived ? "Desarquivar" : "Arquivar"}
                        onClick={() =>
                          void window.worklog.projects
                            .archive(project.id, !project.isArchived)
                            .catch((err) => setErrorMessage(String(err)))
                        }
                      >
                        <Archive size={14} />
                      </button>
                      <button
                        type="button"
                        className="btn btn-icon btn-danger"
                        title="Excluir"
                        onClick={() => setPendingDelete(project)}
                      >
                        <Trash2 size={14} />
                      </button>
                    </div>
                  </div>
                  {index < filteredProjects.length - 1 && (
                    <div className="list-divider" />
                  )}
                </React.Fragment>
              );
            })}
          </div>
        )}
      </div>

      {showingNewForm && (
        <ProjectFormModal
          project={null}
          onClose={() => setShowingNewForm(false)}
          onSaved={() => setErrorMessage(null)}
        />
      )}

      {pendingDelete && (
        <ConfirmModal
          title="Excluir projeto?"
          message="Essa ação também removerá todas as sessões associadas a este projeto."
          onCancel={() => setPendingDelete(null)}
          onConfirm={() => {
            const id = pendingDelete.id;
            setPendingDelete(null);
            void window.worklog.projects
              .delete(id)
              .catch((err) => setErrorMessage(String(err)));
          }}
        />
      )}
    </div>
  );
};
