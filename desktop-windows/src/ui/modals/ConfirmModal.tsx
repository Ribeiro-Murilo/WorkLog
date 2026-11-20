import React from "react";
import { X } from "lucide-react";

interface ConfirmModalProps {
  title: string;
  message: string;
  confirmLabel?: string;
  danger?: boolean;
  onConfirm: () => void;
  onCancel: () => void;
}

export const ConfirmModal: React.FC<ConfirmModalProps> = ({
  title,
  message,
  confirmLabel = "Excluir",
  danger = true,
  onConfirm,
  onCancel
}) => (
  <div className="modal-backdrop" onClick={onCancel}>
    <div className="modal-card" style={{ maxWidth: 420 }} onClick={(e) => e.stopPropagation()}>
      <div className="modal-header">
        <h3>{title}</h3>
        <button type="button" className="btn btn-icon" onClick={onCancel} aria-label="Fechar">
          <X size={15} />
        </button>
      </div>
      <div className="modal-body">
        <p style={{ margin: 0, lineHeight: 1.5 }}>{message}</p>
      </div>
      <div className="modal-footer">
        <button type="button" className="btn" onClick={onCancel}>
          Cancelar
        </button>
        <button
          type="button"
          className={`btn ${danger ? "btn-danger" : "btn-primary"}`}
          onClick={onConfirm}
        >
          {confirmLabel}
        </button>
      </div>
    </div>
  </div>
);
