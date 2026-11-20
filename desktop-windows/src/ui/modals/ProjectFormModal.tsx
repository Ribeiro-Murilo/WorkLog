import React, { useState } from "react";
import { X } from "lucide-react";
import { parseBrazilianDecimal } from "../../shared/format";
import {
  PROJECT_CATEGORY_LABELS,
  PROJECT_STATUS_LABELS,
  type Project,
  type ProjectCategory,
  type ProjectStatus
} from "../../shared/types";

interface ProjectFormModalProps {
  project: Project | null;
  onClose: () => void;
  onSaved: () => void;
}

export const ProjectFormModal: React.FC<ProjectFormModalProps> = ({
  project,
  onClose,
  onSaved
}) => {
  const [name, setName] = useState(project?.name ?? "");
  const [client, setClient] = useState(project?.client ?? "");
  const [dailyRateText, setDailyRateText] = useState(
    project ? String(project.dailyRate).replace(".", ",") : ""
  );
  const [category, setCategory] = useState<ProjectCategory>(project?.category ?? "work");
  const [status, setStatus] = useState<ProjectStatus>(project?.status ?? "active");
  const [tagsText, setTagsText] = useState(project ? project.tags.join(", ") : "");
  const [descriptionText, setDescriptionText] = useState(project?.descriptionText ?? "");
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setErrorMessage(null);
    const rate = dailyRateText.trim() === "" ? 0 : parseBrazilianDecimal(dailyRateText);
    const tags = tagsText
      .split(",")
      .map((t) => t.trim())
      .filter(Boolean);

    setSaving(true);
    try {
      const payload = {
        name,
        client,
        dailyRate: rate,
        category,
        tags,
        descriptionText,
        status
      };
      if (project) {
        await window.worklog.projects.update(project.id, payload);
      } else {
        await window.worklog.projects.create(payload);
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
          <h3>{project ? "Editar Projeto" : "Novo Projeto"}</h3>
          <button type="button" className="btn btn-icon" onClick={onClose} aria-label="Fechar">
            <X size={15} />
          </button>
        </div>

        <form onSubmit={handleSubmit}>
          <div className="modal-body">
            <div className="field-group">
              <label className="field-label">Nome do projeto</label>
              <input
                className="input"
                type="text"
                value={name}
                onChange={(e) => setName(e.target.value)}
                autoFocus
              />
            </div>

            <div className="field-group">
              <label className="field-label">Cliente</label>
              <input
                className="input"
                type="text"
                value={client}
                onChange={(e) => setClient(e.target.value)}
              />
            </div>

            <div className="field-group">
              <label className="field-label">Valor por dia (R$)</label>
              <input
                className="input"
                type="text"
                placeholder="0,00"
                value={dailyRateText}
                onChange={(e) => setDailyRateText(e.target.value)}
              />
            </div>

            <div className="two-col-grid" style={{ marginBottom: 0 }}>
              <div className="field-group">
                <label className="field-label">Categoria</label>
                <select
                  className="select"
                  value={category}
                  onChange={(e) => setCategory(e.target.value as ProjectCategory)}
                >
                  {(Object.keys(PROJECT_CATEGORY_LABELS) as ProjectCategory[]).map((key) => (
                    <option key={key} value={key}>
                      {PROJECT_CATEGORY_LABELS[key]}
                    </option>
                  ))}
                </select>
              </div>

              <div className="field-group">
                <label className="field-label">Status</label>
                <select
                  className="select"
                  value={status}
                  onChange={(e) => setStatus(e.target.value as ProjectStatus)}
                >
                  {(Object.keys(PROJECT_STATUS_LABELS) as ProjectStatus[]).map((key) => (
                    <option key={key} value={key}>
                      {PROJECT_STATUS_LABELS[key]}
                    </option>
                  ))}
                </select>
              </div>
            </div>

            <div className="field-group">
              <label className="field-label">Tags (separadas por vírgula)</label>
              <input
                className="input"
                type="text"
                value={tagsText}
                onChange={(e) => setTagsText(e.target.value)}
              />
            </div>

            <div className="field-group">
              <label className="field-label">Descrição</label>
              <textarea
                className="textarea"
                value={descriptionText}
                onChange={(e) => setDescriptionText(e.target.value)}
              />
            </div>

            {errorMessage && <div className="alert-banner alert-error">{errorMessage}</div>}
          </div>

          <div className="modal-footer">
            <button type="button" className="btn" onClick={onClose}>
              Cancelar
            </button>
            <button type="submit" className="btn btn-primary" disabled={saving}>
              Salvar
            </button>
          </div>
        </form>
      </div>
    </div>
  );
};
