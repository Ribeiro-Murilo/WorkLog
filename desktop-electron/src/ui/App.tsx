import {
  Archive,
  BarChart3,
  BriefcaseBusiness,
  Check,
  Clock3,
  Download,
  FileJson,
  FolderKanban,
  Pause,
  Play,
  Plus,
  RefreshCw,
  Save,
  Search,
  Settings,
  Square,
  Trash2,
  Upload
} from "lucide-react";
import { FormEvent, useEffect, useMemo, useState } from "react";
import { formatDuration, formatMoney, toDateInputValue } from "../shared/format";
import type {
  AppSettings,
  DashboardSummary,
  ExportTable,
  Project,
  ProjectCategory,
  ProjectInput,
  ProjectStatus,
  Session,
  SessionInput,
  TimerState
} from "../shared/types";
import type { AppSnapshot } from "../vite-env";

type View = "dashboard" | "projects" | "sessions" | "reports" | "settings";

const emptyProject: ProjectInput = {
  name: "",
  client: "",
  dailyRate: 0,
  category: "work",
  tags: [],
  descriptionText: "",
  status: "active",
  isArchived: false,
  isFavorite: false
};

function emptySession(projectId = ""): SessionInput {
  const end = new Date();
  const start = new Date(end.getTime() - 60 * 60 * 1000);
  return {
    projectId,
    startTime: toDateInputValue(start),
    endTime: toDateInputValue(end),
    note: ""
  };
}

export function App() {
  const [snapshot, setSnapshot] = useState<AppSnapshot | null>(null);
  const [view, setView] = useState<View>("dashboard");
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);

  useEffect(() => {
    window.worklog.snapshot().then(setSnapshot).catch((err) => setError(String(err.message ?? err)));
    return window.worklog.onSnapshotChanged(setSnapshot);
  }, []);

  useEffect(() => {
    if (!notice) return;
    const timer = window.setTimeout(() => setNotice(null), 2800);
    return () => window.clearTimeout(timer);
  }, [notice]);

  async function refresh() {
    setSnapshot(await window.worklog.snapshot());
  }

  async function run(action: () => Promise<unknown>, message?: string) {
    try {
      setError(null);
      await action();
      await refresh();
      if (message) setNotice(message);
    } catch (err) {
      setError(String(err instanceof Error ? err.message : err));
    }
  }

  if (!snapshot) {
    return <div className="loading">Carregando WorkLog...</div>;
  }

  return (
    <div className={`app theme-${snapshot.settings.theme}`}>
      <aside className="sidebar">
        <div className="brand">
          <div className="brand-mark">W</div>
          <div>
            <strong>WorkLog</strong>
            <span>Windows/Linux</span>
          </div>
        </div>
        <NavButton view="dashboard" current={view} icon={<BarChart3 size={18} />} label="Dashboard" onClick={setView} />
        <NavButton view="projects" current={view} icon={<FolderKanban size={18} />} label="Projetos" onClick={setView} />
        <NavButton view="sessions" current={view} icon={<Clock3 size={18} />} label="Sessões" onClick={setView} />
        <NavButton view="reports" current={view} icon={<Download size={18} />} label="Relatórios" onClick={setView} />
        <NavButton view="settings" current={view} icon={<Settings size={18} />} label="Configurações" onClick={setView} />
        <div className="sidebar-footer">
          <button className="ghost icon-text" onClick={() => run(refresh)}>
            <RefreshCw size={16} /> Atualizar
          </button>
        </div>
      </aside>

      <main className="main">
        <TimerStrip timer={snapshot.timer} projects={snapshot.projects} run={run} />
        {error && <div className="alert error">{error}</div>}
        {notice && <div className="alert success">{notice}</div>}
        {view === "dashboard" && <Dashboard dashboard={snapshot.dashboard} settings={snapshot.settings} />}
        {view === "projects" && <ProjectsView projects={snapshot.projects} run={run} />}
        {view === "sessions" && <SessionsView projects={snapshot.projects} sessions={snapshot.sessions} run={run} />}
        {view === "reports" && <ReportsView snapshot={snapshot} run={run} />}
        {view === "settings" && <SettingsView settings={snapshot.settings} run={run} />}
      </main>
    </div>
  );
}

function NavButton({
  view,
  current,
  icon,
  label,
  onClick
}: {
  view: View;
  current: View;
  icon: React.ReactNode;
  label: string;
  onClick: (view: View) => void;
}) {
  return (
    <button className={`nav ${current === view ? "active" : ""}`} onClick={() => onClick(view)}>
      {icon}
      <span>{label}</span>
    </button>
  );
}

function TimerStrip({
  timer,
  projects,
  run
}: {
  timer: TimerState;
  projects: Project[];
  run: (action: () => Promise<unknown>, message?: string) => Promise<void>;
}) {
  const [selectedProject, setSelectedProject] = useState("");
  const runnableProjects = projects.filter((project) => !project.isArchived);

  useEffect(() => {
    if (!selectedProject && runnableProjects[0]) setSelectedProject(runnableProjects[0].id);
  }, [runnableProjects, selectedProject]);

  return (
    <section className="timer-strip">
      <div>
        <span className="eyebrow">Timer ativo</span>
        <h1>{timer.activeProject ? timer.activeProject.name : "Nenhum projeto em execução"}</h1>
      </div>
      <div className="timer-time">{formatDuration(timer.elapsedSeconds)}</div>
      <select value={selectedProject} onChange={(event) => setSelectedProject(event.target.value)}>
        {runnableProjects.map((project) => (
          <option key={project.id} value={project.id}>
            {project.name} - {project.client}
          </option>
        ))}
      </select>
      <button className="primary icon" disabled={!selectedProject} title="Iniciar" onClick={() => run(() => window.worklog.timer.start(selectedProject))}>
        <Play size={18} />
      </button>
      <button className="icon" disabled={!timer.isRunning} title="Pausar" onClick={() => run(() => window.worklog.timer.pause())}>
        <Pause size={18} />
      </button>
      <button className="icon" disabled={!timer.isRunning} title="Encerrar" onClick={() => run(() => window.worklog.timer.stop())}>
        <Square size={18} />
      </button>
    </section>
  );
}

function Dashboard({ dashboard, settings }: { dashboard: DashboardSummary; settings: AppSettings }) {
  return (
    <section className="view">
      <div className="view-header">
        <div>
          <span className="eyebrow">Resumo</span>
          <h2>Dashboard</h2>
        </div>
      </div>
      <div className="metrics">
        <Metric label="Hoje" value={formatDuration(dashboard.todaySeconds, settings.showSeconds)} />
        <Metric label="Semana" value={formatDuration(dashboard.weekSeconds, settings.showSeconds)} />
        <Metric label="Mês" value={formatDuration(dashboard.monthSeconds, settings.showSeconds)} />
        <Metric label="Valor estimado" value={formatMoney(dashboard.totalValue)} />
      </div>
      <div className="grid two">
        <BucketList title="Tempo por projeto" buckets={dashboard.byProject} />
        <BucketList title="Tempo por cliente" buckets={dashboard.byClient} />
        <BucketList title="Tempo por categoria" buckets={dashboard.byCategory} />
        <RecentSessions sessions={dashboard.recentSessions} />
      </div>
    </section>
  );
}

function Metric({ label, value }: { label: string; value: string }) {
  return (
    <div className="metric">
      <span>{label}</span>
      <strong>{value}</strong>
    </div>
  );
}

function BucketList({ title, buckets }: { title: string; buckets: DashboardSummary["byProject"] }) {
  return (
    <div className="panel">
      <h3>{title}</h3>
      <div className="bucket-list">
        {buckets.length === 0 && <span className="muted">Sem dados registrados.</span>}
        {buckets.map((bucket) => (
          <div className="bucket" key={bucket.label}>
            <span>{bucket.label}</span>
            <strong>{formatDuration(bucket.seconds, false)}</strong>
          </div>
        ))}
      </div>
    </div>
  );
}

function RecentSessions({ sessions }: { sessions: Session[] }) {
  return (
    <div className="panel">
      <h3>Últimas sessões</h3>
      <div className="session-list compact">
        {sessions.map((session) => (
          <div className="session-row" key={session.id}>
            <span>{session.projectName ?? "Sem projeto"}</span>
            <strong>{formatDuration(session.durationSeconds, false)}</strong>
          </div>
        ))}
      </div>
    </div>
  );
}

function ProjectsView({
  projects,
  run
}: {
  projects: Project[];
  run: (action: () => Promise<unknown>, message?: string) => Promise<void>;
}) {
  const [editing, setEditing] = useState<Project | null>(null);
  const [query, setQuery] = useState("");
  const filtered = projects.filter((project) => {
    const haystack = `${project.name} ${project.client} ${project.descriptionText} ${project.tags.join(" ")}`.toLowerCase();
    return haystack.includes(query.toLowerCase());
  });

  return (
    <section className="view split">
      <div className="pane">
        <div className="view-header">
          <div>
            <span className="eyebrow">Cadastro</span>
            <h2>Projetos</h2>
          </div>
          <button className="primary icon-text" onClick={() => setEditing(null)}>
            <Plus size={16} /> Novo
          </button>
        </div>
        <label className="search">
          <Search size={16} />
          <input value={query} onChange={(event) => setQuery(event.target.value)} placeholder="Pesquisar projeto, cliente ou tag" />
        </label>
        <div className="project-list">
          {filtered.map((project) => (
            <button className={`project-item ${editing?.id === project.id ? "selected" : ""}`} key={project.id} onClick={() => setEditing(project)}>
              <BriefcaseBusiness size={18} />
              <span>
                <strong>{project.name}</strong>
                <small>{project.client}</small>
              </span>
              {project.isArchived && <Archive size={15} />}
            </button>
          ))}
        </div>
      </div>
      <ProjectForm
        project={editing}
        onSave={(id, input) => run(() => window.worklog.projects.save(id, input), "Projeto salvo.")}
        onArchive={(id, archived) => run(() => window.worklog.projects.archive(id, archived), archived ? "Projeto arquivado." : "Projeto restaurado.")}
        onDelete={(id) => run(() => window.worklog.projects.delete(id), "Projeto excluído.")}
      />
    </section>
  );
}

function ProjectForm({
  project,
  onSave,
  onArchive,
  onDelete
}: {
  project: Project | null;
  onSave: (id: string | null, input: ProjectInput) => Promise<void>;
  onArchive: (id: string, archived: boolean) => Promise<void>;
  onDelete: (id: string) => Promise<void>;
}) {
  const [form, setForm] = useState<ProjectInput>(emptyProject);
  const [tagText, setTagText] = useState("");

  useEffect(() => {
    setForm(project ? projectToInput(project) : emptyProject);
    setTagText(project?.tags.join(", ") ?? "");
  }, [project]);

  async function submit(event: FormEvent) {
    event.preventDefault();
    await onSave(project?.id ?? null, { ...form, tags: tagText.split(",").map((tag) => tag.trim()).filter(Boolean) });
  }

  return (
    <form className="pane form" onSubmit={submit}>
      <div className="view-header">
        <div>
          <span className="eyebrow">{project ? "Editar" : "Novo"}</span>
          <h2>{project ? project.name : "Projeto"}</h2>
        </div>
        <button className="primary icon-text" type="submit">
          <Save size={16} /> Salvar
        </button>
      </div>
      <Field label="Nome">
        <input value={form.name} onChange={(event) => setForm({ ...form, name: event.target.value })} />
      </Field>
      <Field label="Cliente">
        <input value={form.client} onChange={(event) => setForm({ ...form, client: event.target.value })} />
      </Field>
      <div className="row">
        <Field label="Valor por dia">
          <input type="number" min="0" step="0.01" value={form.dailyRate} onChange={(event) => setForm({ ...form, dailyRate: Number(event.target.value) })} />
        </Field>
        <Field label="Categoria">
          <select value={form.category} onChange={(event) => setForm({ ...form, category: event.target.value as ProjectCategory })}>
            <option value="work">Trabalho</option>
            <option value="personal">Pessoal</option>
          </select>
        </Field>
        <Field label="Status">
          <select value={form.status} onChange={(event) => setForm({ ...form, status: event.target.value as ProjectStatus })}>
            <option value="active">Ativo</option>
            <option value="inProgress">Em execução</option>
            <option value="blocked">Impedimento</option>
            <option value="ready">Pronto</option>
          </select>
        </Field>
      </div>
      <Field label="Tags">
        <input value={tagText} onChange={(event) => setTagText(event.target.value)} placeholder="tag1, tag2" />
      </Field>
      <Field label="Descrição">
        <textarea value={form.descriptionText} onChange={(event) => setForm({ ...form, descriptionText: event.target.value })} />
      </Field>
      <label className="checkline">
        <input type="checkbox" checked={Boolean(form.isFavorite)} onChange={(event) => setForm({ ...form, isFavorite: event.target.checked })} />
        Favorito
      </label>
      {project && (
        <div className="actions-row">
          <button type="button" className="icon-text" onClick={() => onArchive(project.id, !project.isArchived)}>
            <Archive size={16} /> {project.isArchived ? "Restaurar" : "Arquivar"}
          </button>
          <button type="button" className="danger icon-text" onClick={() => onDelete(project.id)}>
            <Trash2 size={16} /> Excluir
          </button>
        </div>
      )}
    </form>
  );
}

function SessionsView({
  projects,
  sessions,
  run
}: {
  projects: Project[];
  sessions: Session[];
  run: (action: () => Promise<unknown>, message?: string) => Promise<void>;
}) {
  const [editing, setEditing] = useState<Session | null>(null);
  return (
    <section className="view split">
      <div className="pane">
        <div className="view-header">
          <div>
            <span className="eyebrow">Histórico</span>
            <h2>Sessões</h2>
          </div>
          <button className="primary icon-text" onClick={() => setEditing(null)}>
            <Plus size={16} /> Manual
          </button>
        </div>
        <div className="session-list">
          {sessions.map((session) => (
            <button className={`session-item ${editing?.id === session.id ? "selected" : ""}`} key={session.id} onClick={() => setEditing(session)}>
              <span>
                <strong>{session.projectName ?? "Sem projeto"}</strong>
                <small>{new Date(session.startTime).toLocaleString("pt-BR")}</small>
              </span>
              <strong>{session.status === "running" ? "em andamento" : formatDuration(session.durationSeconds, false)}</strong>
            </button>
          ))}
        </div>
      </div>
      <SessionForm
        projects={projects.filter((project) => !project.isArchived)}
        session={editing}
        onSave={(id, input) =>
          run(() => (id ? window.worklog.sessions.updateManual(id, input) : window.worklog.sessions.addManual(input)), "Sessão salva.")
        }
        onDelete={(id) => run(() => window.worklog.sessions.delete(id), "Sessão excluída.")}
      />
    </section>
  );
}

function SessionForm({
  projects,
  session,
  onSave,
  onDelete
}: {
  projects: Project[];
  session: Session | null;
  onSave: (id: string | null, input: SessionInput) => Promise<void>;
  onDelete: (id: string) => Promise<void>;
}) {
  const [form, setForm] = useState<SessionInput>(emptySession(projects[0]?.id ?? ""));

  useEffect(() => {
    setForm(
      session
        ? {
            projectId: session.projectId ?? projects[0]?.id ?? "",
            startTime: toDateInputValue(new Date(session.startTime)),
            endTime: toDateInputValue(new Date(session.endTime ?? new Date())),
            note: session.note
          }
        : emptySession(projects[0]?.id ?? "")
    );
  }, [projects, session]);

  async function submit(event: FormEvent) {
    event.preventDefault();
    await onSave(session?.id ?? null, {
      ...form,
      startTime: new Date(form.startTime).toISOString(),
      endTime: new Date(form.endTime).toISOString()
    });
  }

  return (
    <form className="pane form" onSubmit={submit}>
      <div className="view-header">
        <div>
          <span className="eyebrow">{session ? "Editar" : "Adicionar"}</span>
          <h2>Sessão manual</h2>
        </div>
        <button className="primary icon-text" type="submit" disabled={!form.projectId}>
          <Check size={16} /> Salvar
        </button>
      </div>
      <Field label="Projeto">
        <select value={form.projectId} onChange={(event) => setForm({ ...form, projectId: event.target.value })}>
          {projects.map((project) => (
            <option key={project.id} value={project.id}>
              {project.name} - {project.client}
            </option>
          ))}
        </select>
      </Field>
      <div className="row">
        <Field label="Início">
          <input type="datetime-local" value={form.startTime} onChange={(event) => setForm({ ...form, startTime: event.target.value })} />
        </Field>
        <Field label="Fim">
          <input type="datetime-local" value={form.endTime} onChange={(event) => setForm({ ...form, endTime: event.target.value })} />
        </Field>
      </div>
      <Field label="Nota">
        <textarea value={form.note} onChange={(event) => setForm({ ...form, note: event.target.value })} />
      </Field>
      {session && session.status !== "running" && (
        <button type="button" className="danger icon-text" onClick={() => onDelete(session.id)}>
          <Trash2 size={16} /> Excluir sessão
        </button>
      )}
    </form>
  );
}

function ReportsView({
  snapshot,
  run
}: {
  snapshot: AppSnapshot;
  run: (action: () => Promise<unknown>, message?: string) => Promise<void>;
}) {
  const table = useMemo<ExportTable>(() => {
    return {
      title: "worklog-sessoes",
      headers: ["Projeto", "Cliente", "Início", "Fim", "Duração", "Status", "Nota"],
      rows: snapshot.sessions.map((session) => [
        session.projectName ?? "",
        session.projectClient ?? "",
        new Date(session.startTime).toLocaleString("pt-BR"),
        session.endTime ? new Date(session.endTime).toLocaleString("pt-BR") : "",
        formatDuration(session.durationSeconds, false),
        session.status,
        session.note
      ])
    };
  }, [snapshot.sessions]);

  return (
    <section className="view">
      <div className="view-header">
        <div>
          <span className="eyebrow">Dados</span>
          <h2>Relatórios e backup</h2>
        </div>
      </div>
      <div className="grid two">
        <div className="panel action-panel">
          <h3>Exportar sessões</h3>
          <p>Gera uma planilha com as sessões registradas na base local.</p>
          <div className="actions-row">
            <button className="icon-text" onClick={() => run(() => window.worklog.export.table(table, "csv"), "CSV exportado.")}>
              <Download size={16} /> CSV
            </button>
            <button className="icon-text" onClick={() => run(() => window.worklog.export.table(table, "excel"), "Excel XML exportado.")}>
              <Download size={16} /> Excel XML
            </button>
          </div>
        </div>
        <div className="panel action-panel">
          <h3>Backup JSON</h3>
          <p>Formato local-first para migração futura entre apps e API.</p>
          <div className="actions-row">
            <button className="icon-text" onClick={() => run(() => window.worklog.backup.export(), "Backup exportado.")}>
              <FileJson size={16} /> Exportar
            </button>
            <button className="icon-text" onClick={() => run(() => window.worklog.backup.import(), "Backup importado.")}>
              <Upload size={16} /> Importar
            </button>
          </div>
        </div>
      </div>
    </section>
  );
}

function SettingsView({
  settings,
  run
}: {
  settings: AppSettings;
  run: (action: () => Promise<unknown>, message?: string) => Promise<void>;
}) {
  return (
    <section className="view">
      <div className="view-header">
        <div>
          <span className="eyebrow">Desktop</span>
          <h2>Configurações</h2>
        </div>
      </div>
      <div className="panel settings-panel">
        <Field label="Tema">
          <select value={settings.theme} onChange={(event) => run(() => window.worklog.settings.update({ theme: event.target.value as AppSettings["theme"] }))}>
            <option value="system">Sistema</option>
            <option value="light">Claro</option>
            <option value="dark">Escuro</option>
          </select>
        </Field>
        <label className="checkline">
          <input
            type="checkbox"
            checked={settings.showSeconds}
            onChange={(event) => run(() => window.worklog.settings.update({ showSeconds: event.target.checked }))}
          />
          Mostrar segundos nos contadores
        </label>
        <label className="checkline">
          <input
            type="checkbox"
            checked={settings.launchAtLogin}
            onChange={(event) => run(() => window.worklog.settings.update({ launchAtLogin: event.target.checked }))}
          />
          Iniciar com o sistema
        </label>
        <Field label="Pausa automática por inatividade (minutos)">
          <input
            type="number"
            min="1"
            value={settings.idleTimeoutMinutes}
            onChange={(event) => run(() => window.worklog.settings.update({ idleTimeoutMinutes: Number(event.target.value) }))}
          />
        </Field>
      </div>
    </section>
  );
}

function Field({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <label className="field">
      <span>{label}</span>
      {children}
    </label>
  );
}

function projectToInput(project: Project): ProjectInput {
  return {
    name: project.name,
    client: project.client,
    dailyRate: project.dailyRate,
    category: project.category,
    tags: project.tags,
    descriptionText: project.descriptionText,
    status: project.status,
    isArchived: project.isArchived,
    isFavorite: project.isFavorite
  };
}
