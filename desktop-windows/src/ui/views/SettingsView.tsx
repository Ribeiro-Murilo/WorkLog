import React, { useEffect, useMemo, useState } from "react";
import {
  FileText,
  HardDrive,
  Info,
  Keyboard,
  Settings as SettingsIcon
} from "lucide-react";
import { formatDateTimeShort } from "../../shared/format";
import {
  APP_DISPLAY_MODE_LABELS,
  APP_THEME_LABELS,
  SHORTCUT_ACTION_LABELS,
  TIME_FORMAT_LABELS,
  type AppDisplayMode,
  type AppSnapshot,
  type AppTheme,
  type ShortcutAction,
  type TimeFormatPreference
} from "../../shared/types";

interface SettingsViewProps {
  snapshot: AppSnapshot;
  logoSrc: string;
}

type SettingsTab = "general" | "shortcuts" | "billing" | "backup" | "about";

const IDLE_TIMEOUT_OPTIONS = [5, 10, 15, 30, 60];

function keyEventToAccelerator(e: React.KeyboardEvent): string | null {
  const ignoreKeys = new Set(["Control", "Shift", "Alt", "Meta", "OS"]);
  if (ignoreKeys.has(e.key)) return null;

  const mods: string[] = [];
  if (e.ctrlKey || e.metaKey) mods.push("CommandOrControl");
  if (e.altKey) mods.push("Alt");
  if (e.shiftKey) mods.push("Shift");
  if (mods.length === 0) return null;

  let key = e.key;
  if (key === " ") key = "Space";
  else if (key.length === 1) key = key.toUpperCase();
  return [...mods, key].join("+");
}

function formatAcceleratorLabel(acc: string): string {
  return acc.replace(/CommandOrControl/g, "Ctrl");
}

export const SettingsView: React.FC<SettingsViewProps> = ({ snapshot, logoSrc }) => {
  const [tab, setTab] = useState<SettingsTab>("general");
  const [recordingAction, setRecordingAction] = useState<ShortcutAction | null>(null);
  const [issuerName, setIssuerName] = useState(snapshot.settings.invoiceIssuerName);
  const [issuerDetails, setIssuerDetails] = useState(snapshot.settings.invoiceIssuerDetails);
  const [statusMessage, setStatusMessage] = useState<string | null>(null);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  useEffect(() => {
    setIssuerName(snapshot.settings.invoiceIssuerName);
    setIssuerDetails(snapshot.settings.invoiceIssuerDetails);
  }, [snapshot.settings.invoiceIssuerName, snapshot.settings.invoiceIssuerDetails]);

  const sortedShortcuts = useMemo(
    () =>
      [...snapshot.shortcuts].sort((a, b) =>
        SHORTCUT_ACTION_LABELS[a.action].localeCompare(SHORTCUT_ACTION_LABELS[b.action], "pt-BR")
      ),
    [snapshot.shortcuts]
  );

  const saveSettings = async (patch: Parameters<typeof window.worklog.settings.save>[0]) => {
    try {
      setErrorMessage(null);
      await window.worklog.settings.save(patch);
    } catch (err) {
      setErrorMessage(err instanceof Error ? err.message : String(err));
    }
  };

  return (
    <div>
      <div className="page-header">
        <h1 className="page-title">Configurações</h1>
      </div>

      <div className="tabs-bar">
        <button
          type="button"
          className={`tab-btn ${tab === "general" ? "active" : ""}`}
          onClick={() => setTab("general")}
        >
          <SettingsIcon size={15} /> Geral
        </button>
        <button
          type="button"
          className={`tab-btn ${tab === "shortcuts" ? "active" : ""}`}
          onClick={() => setTab("shortcuts")}
        >
          <Keyboard size={15} /> Atalhos
        </button>
        <button
          type="button"
          className={`tab-btn ${tab === "billing" ? "active" : ""}`}
          onClick={() => setTab("billing")}
        >
          <FileText size={15} /> Faturamento
        </button>
        <button
          type="button"
          className={`tab-btn ${tab === "backup" ? "active" : ""}`}
          onClick={() => setTab("backup")}
        >
          <HardDrive size={15} /> Backup
        </button>
        <button
          type="button"
          className={`tab-btn ${tab === "about" ? "active" : ""}`}
          onClick={() => setTab("about")}
        >
          <Info size={15} /> Sobre
        </button>
      </div>

      {errorMessage && (
        <div className="alert-banner alert-error" style={{ marginBottom: 14 }}>
          {errorMessage}
        </div>
      )}
      {statusMessage && (
        <div
          className="alert-banner"
          style={{
            marginBottom: 14,
            background: "var(--success-bg)",
            color: "var(--success)"
          }}
        >
          {statusMessage}
        </div>
      )}

      {tab === "general" && (
        <div className="card" style={{ display: "flex", flexDirection: "column", gap: 16 }}>
          <label className="checkbox-line" style={{ justifyContent: "space-between" }}>
            <span>Inicializar junto com o Windows</span>
            <input
              type="checkbox"
              checked={snapshot.settings.launchAtLogin}
              onChange={(e) => void saveSettings({ launchAtLogin: e.target.checked })}
            />
          </label>

          <div className="list-divider" />

          <div className="kv-row">
            <div>
              <div>Onde exibir o WorkLog</div>
              <div className="small muted">
                No modo Notch, uma barrinha compacta permanece fixa no topo da tela.
              </div>
            </div>
            <select
              className="select"
              value={snapshot.settings.displayMode}
              onChange={(e) =>
                void saveSettings({ displayMode: e.target.value as AppDisplayMode })
              }
            >
              {(Object.keys(APP_DISPLAY_MODE_LABELS) as AppDisplayMode[]).map((mode) => (
                <option key={mode} value={mode}>
                  {APP_DISPLAY_MODE_LABELS[mode]}
                </option>
              ))}
            </select>
          </div>

          {snapshot.settings.displayMode === "notch" && snapshot.displays.length > 0 && (
            <div className="kv-row">
              <span>Monitor da barra superior</span>
              <select
                className="select"
                value={snapshot.settings.notchDisplayId ?? ""}
                onChange={(e) =>
                  void saveSettings({ notchDisplayId: e.target.value || null })
                }
              >
                <option value="">Monitor principal automático</option>
                {snapshot.displays.map((d) => (
                  <option key={d.id} value={d.id}>
                    {d.label} ({d.bounds.width}×{d.bounds.height})
                  </option>
                ))}
              </select>
            </div>
          )}

          <div className="list-divider" />

          <div className="kv-row">
            <span>Pausa automática por inatividade</span>
            <select
              className="select"
              value={snapshot.settings.idleTimeoutMinutes}
              onChange={(e) =>
                void saveSettings({ idleTimeoutMinutes: Number(e.target.value) })
              }
            >
              {IDLE_TIMEOUT_OPTIONS.map((min) => (
                <option key={min} value={min}>
                  {min} minutos
                </option>
              ))}
            </select>
          </div>

          <label className="checkbox-line" style={{ justifyContent: "space-between" }}>
            <span>Mostrar segundos</span>
            <input
              type="checkbox"
              checked={snapshot.settings.showSeconds}
              onChange={(e) => void saveSettings({ showSeconds: e.target.checked })}
            />
          </label>

          <div className="kv-row">
            <span>Tema</span>
            <select
              className="select"
              value={snapshot.settings.theme}
              onChange={(e) => void saveSettings({ theme: e.target.value as AppTheme })}
            >
              {(Object.keys(APP_THEME_LABELS) as AppTheme[]).map((theme) => (
                <option key={theme} value={theme}>
                  {APP_THEME_LABELS[theme]}
                </option>
              ))}
            </select>
          </div>

          <div className="kv-row">
            <span>Formato de hora</span>
            <select
              className="select"
              value={snapshot.settings.timeFormat}
              onChange={(e) =>
                void saveSettings({ timeFormat: e.target.value as TimeFormatPreference })
              }
            >
              {(Object.keys(TIME_FORMAT_LABELS) as TimeFormatPreference[]).map((fmt) => (
                <option key={fmt} value={fmt}>
                  {TIME_FORMAT_LABELS[fmt]}
                </option>
              ))}
            </select>
          </div>

          <label className="checkbox-line" style={{ justifyContent: "space-between" }}>
            <span>Incluir logo do app nos PDFs</span>
            <input
              type="checkbox"
              checked={snapshot.settings.includeLogoInPDF}
              onChange={(e) => void saveSettings({ includeLogoInPDF: e.target.checked })}
            />
          </label>
        </div>
      )}

      {tab === "shortcuts" && (
        <div className="card" style={{ display: "flex", flexDirection: "column", gap: 12 }}>
          <div className="small muted">
            Clique no botão do atalho e pressione a nova combinação (ex.: Ctrl + Shift + S).
          </div>
          {sortedShortcuts.map((binding) => {
            const isRecording = recordingAction === binding.action;
            return (
              <div key={binding.action} className="kv-row">
                <span>{SHORTCUT_ACTION_LABELS[binding.action]}</span>
                <button
                  type="button"
                  className={`btn shortcut-recorder-btn ${isRecording ? "recording" : ""}`}
                  onClick={() => setRecordingAction(binding.action)}
                  onBlur={() => {
                    if (isRecording) setRecordingAction(null);
                  }}
                  onKeyDown={(e) => {
                    if (!isRecording) return;
                    e.preventDefault();
                    e.stopPropagation();
                    if (e.key === "Escape") {
                      setRecordingAction(null);
                      return;
                    }
                    const acc = keyEventToAccelerator(e);
                    if (acc) {
                      setRecordingAction(null);
                      void window.worklog.settings.updateShortcut(binding.action, acc);
                    }
                  }}
                >
                  {isRecording
                    ? "Pressione o atalho…"
                    : formatAcceleratorLabel(binding.accelerator)}
                </button>
              </div>
            );
          })}
        </div>
      )}

      {tab === "billing" && (
        <div className="card" style={{ display: "flex", flexDirection: "column", gap: 12 }}>
          <div className="field-label">Emissor da nota</div>
          <div className="field-group">
            <label className="field-label">Nome do emissor</label>
            <input
              className="input"
              type="text"
              value={issuerName}
              onChange={(e) => {
                setIssuerName(e.target.value);
                void saveSettings({ invoiceIssuerName: e.target.value });
              }}
            />
          </div>
          <div className="field-group">
            <label className="field-label">Dados adicionais</label>
            <textarea
              className="textarea"
              value={issuerDetails}
              onChange={(e) => {
                setIssuerDetails(e.target.value);
                void saveSettings({ invoiceIssuerDetails: e.target.value });
              }}
            />
          </div>
          <div className="small muted">
            Aparecem no cabeçalho das notas de faturamento. Ex.: CPF/CNPJ, PIX, endereço.
          </div>
        </div>
      )}

      {tab === "backup" && (
        <div className="card" style={{ display: "flex", flexDirection: "column", gap: 14 }}>
          <div className="field-label">Backup completo (compatível com macOS e Windows)</div>
          <div className="toolbar-actions">
            <button
              type="button"
              className="btn btn-primary"
              onClick={() => {
                setStatusMessage(null);
                setErrorMessage(null);
                void window.worklog.backup
                  .exportJson()
                  .then((res) => {
                    if (res.saved) setStatusMessage("Backup exportado com sucesso.");
                  })
                  .catch((err) => setErrorMessage(String(err)));
              }}
            >
              Exportar backup…
            </button>
            <button
              type="button"
              className="btn"
              onClick={() => {
                setStatusMessage(null);
                setErrorMessage(null);
                void window.worklog.backup.importJson().then((res) => {
                  if (res.imported) setStatusMessage("Backup importado com sucesso.");
                  else if (res.error) setErrorMessage(res.error);
                });
              }}
            >
              Importar backup…
            </button>
          </div>
          {snapshot.settings.lastBackupDate && (
            <div className="small muted">
              Último backup exportado em{" "}
              {formatDateTimeShort(
                snapshot.settings.lastBackupDate,
                snapshot.settings.timeFormat
              )}
            </div>
          )}
          <div className="list-divider" />
          <div>
            <div className="field-label" style={{ marginBottom: 4 }}>
              Exportação de relatórios
            </div>
            <div className="small muted">
              Utilize a tela de Relatórios para exportar sessões em CSV, Excel ou PDF.
            </div>
          </div>
        </div>
      )}

      {tab === "about" && (
        <div
          className="card"
          style={{
            display: "flex",
            flexDirection: "column",
            alignItems: "center",
            justifyContent: "center",
            gap: 10,
            padding: 36,
            textAlign: "center"
          }}
        >
          <img
            src={logoSrc}
            alt="WorkLog"
            style={{ width: 88, height: 88, borderRadius: 20 }}
          />
          <h2 style={{ margin: "4px 0 0", fontSize: 22 }}>WorkLog</h2>
          <div className="small muted">Versão {snapshot.appVersion} (Windows)</div>
          <div className="small muted">
            Controle pessoal de tempo em projetos e demandas.
          </div>
        </div>
      )}
    </div>
  );
};
