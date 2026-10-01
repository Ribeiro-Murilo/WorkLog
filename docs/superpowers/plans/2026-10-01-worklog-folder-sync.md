# WorkLog Folder Sync Implementation Plan

> **For agentic workers:** Use superpowers:subagent-driven-development. Execute the approved plan in the current branch; the user's explicit parallel-work preference authorizes disjoint implementation tasks in parallel.

**Goal:** Sincronizar registros entre Macs através de uma pasta escolhida no iCloud Drive sem Apple Developer Program.

**Architecture:** SwiftData permanece local. Um diário de operações imutáveis com ancestralidade permite importação idempotente, exclusões e conflitos; checkpoints são transacionais junto aos registros.

**Tech Stack:** Swift, SwiftData, SwiftUI, Foundation, Swift Testing; sem dependências novas.

**Spec:** `docs/superpowers/specs/2026-10-01-worklog-folder-sync-design.md`

## Global Constraints

- Branch atual; sem branch/PR/publicação e sem coautores em commits.
- Sem CloudKit, container iCloud próprio ou adesão Apple Developer.
- UUIDs e valores preservados; sessões ativas e preferências de máquina locais.
- Falhas não apagam dados; conflitos são preservados e visíveis.
- Testes via diretórios temporários, nunca na pasta iCloud pessoal do usuário.

## Review Focus

- Interrupção entre persistência e publicação: operações pendentes devem sobreviver.
- Arquivos fora de ordem ou futuros: não materializar dados incompletos.
- Exclusões em cascata e cronômetro ativo: não ressuscitar filhos nem perder sessão.
- Dois Macs com dados iniciais/edições concorrentes: não sobrescrever silenciosamente.
- Pasta alterada/indisponível e falha de save: preservar bancos e estados anteriores.

## Task 1: Protocolo e integração de versões

**Files:** `WorkLog/Sync/SyncProtocol.swift`, `WorkLog/Sync/SyncJournal.swift`, `WorkLogTests/SyncJournalTests.swift`.

**Interfaces:**
- `SyncEntity: String, Codable, CaseIterable, Sendable` cases project/session/comment/reportPreset/invoice/billingSettings; `displayName: String`.
- `SyncRecordKey: Codable, Hashable, Sendable` with `entity: SyncEntity`, `id: String`, memberwise init.
- `SyncOperation: Codable, Equatable, Identifiable, Sendable` with `formatVersion: Int`, `id: UUID`, `deviceID: UUID`, `key: SyncRecordKey`, `parents: [UUID]`, `payload: Data?`, `timestamp: Date`; initializer with defaults for version=1/id/timestamp/parents.
- `SyncRecordChange: Sendable` with key/payload and memberwise init.
- `SyncConflict: Identifiable, Sendable` with `key`, `versions: [SyncOperation]`, computed `id: SyncRecordKey`.
- `FolderSyncState: Codable, Sendable` default init, `operations: [SyncOperation]`, `baseline: [SyncRecordKey: Data]`.
- State methods: `captureLocal(_ snapshot: [SyncRecordKey: Data], deviceID: UUID, now: Date) throws -> [SyncOperation]`; `ingest(_ incoming: [SyncOperation]) throws`; `resolvedChanges() -> [SyncRecordChange]`; `resolve(key: SyncRecordKey, payload: Data?, deviceID: UUID, now: Date) throws -> SyncOperation`; `conflicts: [SyncConflict]`; `pendingDependencyCount: Int`.

- [x] Write and run meaningful failing tests for causal edits vs concurrent versions, delete vs update, duplicate replay and missing ancestors.
- [x] Implement validation, deterministic heads, missing dependencies, same-content convergence and explicit conflict resolutions.
- [x] Verify protocol tests; parent registers Xcode test files and runs full suite.

## Task 2: Adaptador SwiftData e backup completo

**Files:** `WorkLog/Sync/SyncRecordStore.swift`, `WorkLog/Sync/SyncRecordPayloads.swift` (split by responsibility if needed), `WorkLog/Services/BackupService.swift`, `WorkLogTests/SyncRecordStoreTests.swift`, `WorkLogTests/BackupServiceTests.swift`.

**Interfaces:**
- `@Model final class FolderSyncMetadata` with defaults; schema registration belongs to parent.
- `@MainActor protocol FolderSyncRecordStoreProtocol`: `snapshot() throws -> [SyncRecordKey: Data]`; `apply(_ changes: [SyncRecordChange]) throws` stages only, no save; `loadState(scope: String) throws -> FolderSyncState?`; `saveState(_ state: FolderSyncState, scope: String) throws` saves records+checkpoint atomically; `rollback()`; `duplicateInvoiceNumbers() throws -> [SyncInvoiceCollision]`; `renumberInvoice(id: UUID) throws`.
- `SyncInvoiceCollision: Identifiable` has number:Int, invoices:[SyncInvoiceReference], id:Int; `SyncInvoiceReference: Identifiable` has id:UUID, client:String.
- `SwiftDataSyncRecordStore(modelContext: ModelContext)` implements protocol. Export payloads canonically (sorted keys, full dates), preserving all persisted business fields. Filter running sessions, reject incoming running sessions. Missing project without known tombstone defers import via descriptive error; known project tombstones suppress descendants. Block project deletion when local session is running. Reconstruct relationships before children; deletions are ordered safely.
- `BackupService(modelContext: ModelContext)` replaces existing repository init (only DependencyContainer uses old init). Full versioned JSON export/import plus legacy projects/sessions decoding, idempotence and one transaction.

- [x] Write failing tests for roundtrip all shared models, running sessions exclusion, machine settings preservation, out-of-order parents, cascade deletes and invoice counters.
- [x] Implement payload mapping, transactional checkpoint and collision correction.
- [x] Add backup tests before implementing full archive/legacy import; verify atomic and idempotent imports.
- [x] Verify focused tests after protocol is available; parent controls Xcode builds to avoid concurrent build database access.

## Task 3: Transporte por arquivos e serviço automático

**Files:** `WorkLog/Sync/FolderSyncFileStore.swift`, `WorkLog/Sync/FolderSyncService.swift`, `WorkLogTests/FolderSyncServiceTests.swift`.

**Interfaces:** `@MainActor @Observable final class FolderSyncService(recordStore: any FolderSyncRecordStoreProtocol, userDefaults: UserDefaults = .standard)`, folder configuration, async synchronize/resolve, persistent scope/device/bookmark; filesystem actor uses coordinated reads/writes and atomic immutable publication.

- [x] Add failing tests using separate local banks and a temporary folder: two-way sync, retry, delete, conflicts/resolution, restart and invalid files.
- [x] Implement capture/checkpoint first, publish pending operations, ingest, apply resolved records/checkpoint in one save. Keep unresolved versions intact. Reentrancy guard and periodic task while app open.
- [x] Preserve checkpoints and access across folder changes/disabling; report verification versus actual remote delivery distinctly.
- [x] Verify service tests and failure scenarios.

## Task 4: Configurações, integração e revisão

**Files:** `WorkLog/Settings/FolderSyncSettingsView.swift`, `WorkLog/Settings/SettingsRootView.swift`, `WorkLog/Core/DI/DependencyContainer.swift`, `WorkLog/Persistence/PersistenceController.swift`, `WorkLog/App/WorkLogApp.swift`, `WorkLog.xcodeproj/project.pbxproj`, README.

- [x] Register local metadata in schema with cloudKitDatabase .none, create service in DI, start it only in live app lifecycle.
- [x] Add native settings tab, folder selection, check/disconnect, conflict versions and invoice renumber actions. Follow existing SwiftUI Form style and accessibility.
- [x] Register test sources in existing explicit PBX test group; no dependency, bundle or signing changes.
- [x] Execute whole unit suite, Debug and Release build; independent review and fix actionable findings.
- [x] Document setup and actual validation; leave real cross-Mac iCloud transport clearly unverified if unavailable.

## Resultado da execução

- Código implementado na branch `main` e preparado para a release 0.1.6 (build 8).
- Suíte integrada: 87 testes aprovados, nenhuma falha ou teste ignorado.
- Builds Debug e Release concluídos com sucesso.
- Testes reproduziram antes das correções os casos de ancestralidade pendente,
  projeto em conflito, emissor desatualizado e resolução de filho indisponível.
- Prévia nativa das configurações inspecionada com estado vazio e conflito.
- Ensaio real do transporte iCloud em dois Macs permanece pendente; os testes
  usam pastas temporárias e bancos locais separados.

- Revisão da release corrigiu a recarga das preferências e dos atalhos após
  restaurar backup, além da atualização do menu após alterações sincronizadas.
- Pacote Release universal (Intel e Apple Silicon), com assinatura EdDSA
  verificada contra a chave pública incorporada no app.
- Proteções no `.gitignore` cobrem dados de sincronização, backups e bancos locais.
