# WorkLog

Aplicativo nativo para macOS, de uso pessoal, para controle de tempo em projetos e demandas através de um cronômetro integrado à Menu Bar.

## Tecnologias

Swift, SwiftUI, SwiftData, MenuBarExtra, Observation, Async/Await. AppKit e Carbon são usados apenas onde não há substituto em SwiftUI (recorte de tecla global, detecção de inatividade, exportação em PDF/Excel).

## Arquitetura

MVVM + Repository Pattern + Dependency Injection, com separação completa de responsabilidades:

```
Model        → structs/@Model (SwiftData) desacoplados de UI e persistência
Repository   → única camada que fala com o ModelContext (CRUD + queries)
Service      → regras de negócio que não pertencem a um repositório específico
                (Timer, Validação, Idle, Atalhos, Exportação, Backup, Launch at Login)
ViewModel    → @Observable, MainActor, orquestra Repository/Service para a View
View         → SwiftUI puro, sem lógica de negócio
```

Toda dependência é resolvida por um único `DependencyContainer` (`Core/DI`), injetado via `Environment` do SwiftUI. Não há singletons implícitos além do `PersistenceController` (o container SwiftData em si).

## Estrutura de pastas

```
WorkLog/
  App/            WorkLogApp (entry point), ContentView
  Core/
    DI/           DependencyContainer, EnvironmentKey
    Extensions/   TimeInterval/DateFormatter helpers
    Utilities/
  Models/         Project, Session, AppSettings, ShortcutBinding, KeyCombo, enums
  Persistence/     PersistenceController (ModelContainer)
  Repositories/   ProjectRepository, SessionRepository, SettingsRepository, ShortcutBindingRepository
  Services/       TimerService, IdleDetectionService, ValidationService,
                  ExportService, ShortcutsService, LaunchAtLoginService, BackupService
  ViewModels/     Um ViewModel por tela/feature
  MenuBar/        Label e Popover da Menu Bar
  Dashboard/      Janela principal com Sidebar
  Projects/       Lista, formulário e detalhe de projetos
  Timer/          Formulário de sessão manual
  Reports/        Relatórios com filtros e exportação
  Settings/       Preferências, atalhos, backup
  Components/     Views reutilizáveis (linhas de projeto/sessão, cards, botões)
WorkLogTests/     Testes unitários (Swift Testing)
WorkLogUITests/   Testes de interface (XCTest/XCUITest)
```

## Fluxo do aplicativo

1. `WorkLogApp` cria o `PersistenceController` (ModelContainer único) e o `DependencyContainer`.
2. Três `Scene`s são declaradas: `WindowGroup(id: "dashboard")`, `MenuBarExtra` (estilo `.window`, aparência de popover) e `Settings`.
3. O app roda como agente de UI (`LSUIElement = YES`): sem ícone no Dock, residente apenas na Menu Bar.
4. Todas as telas recebem o mesmo `DependencyContainer` via `.environment(\.dependencies, ...)`, garantindo uma única fonte de verdade para repositórios e serviços.

## Fluxo do Timer

Regras de negócio centralizadas em `TimerService`:

- Apenas **uma sessão pode estar com status `.running`** em todo o app.
- `start(project:)` fecha (pausa) a sessão em execução atual, se houver, e cria uma **nova** `Session` para o projeto informado — cada intervalo iniciado/pausado é uma sessão independente (ex.: 08:00–09:15, 10:30–12:00).
- `pause()` fecha a sessão atual com status `.paused` e zera o estado ativo.
- `resume()` localiza o projeto da última sessão e chama `start(project:)` novamente, criando uma nova sessão.
- `stop()` fecha a sessão atual com status `.completed`.
- `addManualSession(...)` valida (via `ValidationService`) e verifica sobreposição de horário (via `SessionRepository.hasOverlap`) antes de inserir.
- Pausas automáticas: `IdleDetectionService` observa `NSWorkspace` (sono do sistema, tela bloqueada) e faz polling do tempo de inatividade via `CGEventSource`; ao disparar, chama `TimerService.pause()`.

## Fluxo do Menu Bar

- `MenuBarLabelView`: mostra apenas o ícone quando não há timer ativo; mostra `"<projeto> • <tempo>"` quando há.
- `MenuBarPopoverView`: projeto atual + tempo + iniciar/pausar/encerrar, projetos favoritos/recentes (início rápido de timer), tempo total do dia, atalhos para Dashboard/Configurações/Sair. Também registra os atalhos globais (Carbon HotKey API) na primeira exibição.

## Fluxo de Persistência

- `PersistenceController` define o `Schema` único (`Project`, `Session`, `AppSettings`, `ShortcutBinding`) e cria o `ModelContainer` (disco, `isStoredInMemoryOnly: false`).
- Toda escrita passa por um `Repository`, que chama `modelContext.save()` imediatamente após a mutação — não há estado temporário não persistido.
- Consultas usam `#Predicate`/`FetchDescriptor` do SwiftData. **Atenção:** comparar um enum (`SessionStatus`/`ProjectStatus`) diretamente dentro de `#Predicate` provocou uma falha em tempo de execução nesta toolchain (Xcode 26 SDK); nesse caso específico (`SessionRepository.fetchActiveSession`) a filtragem é feita em memória após um fetch simples.

## Decisões arquiteturais

- **Sem dependências de terceiros (SPM):** atalhos globais usam a Carbon Event Manager API (`RegisterEventHotKey`) em vez de bibliotecas como KeyboardShortcuts, pois o app deve usar exclusivamente as tecnologias listadas no briefing.
- **Exportação Excel sem biblioteca externa:** gerada como SpreadsheetML 2003 XML (`.xml` com `progid="Excel.Sheet"`), formato nativamente aberto pelo Excel sem depender de bibliotecas de geração de `.xlsx`.
- **Backup em JSON:** `BackupService` exporta/importa todo o dataset (projetos + sessões) em JSON simples, mantendo a persistência SwiftData como única fonte de verdade em tempo de execução.
- **`#Index` do SwiftData removido dos models:** a mesma toolchain apresentou uma falha (`Can't create an index element with composite property`) ao declarar índices sobre propriedades baseadas em enum. Os índices foram removidos; para o volume de dados de uso pessoal (milhares de projetos, centenas de milhares de sessões) o impacto é aceitável, mas é um ponto a revisitar em versões futuras do SDK.

## Testes

- `WorkLogTests` (Swift Testing): regras de negócio do `TimerService` (timer único, auto-pausa, validação/sobreposição de sessão manual), `ValidationService`, `ProjectRepository`, `SessionRepository`, `ExportService` (CSV/Excel/PDF). 25 testes, todos passando.
- `WorkLogUITests` (XCTest/XCUITest): smoke test de lançamento do app. **Limitação conhecida:** a execução de UI Tests neste ambiente falha por incompatibilidade de Team ID de assinatura entre o app principal e o runner de testes gerado automaticamente pelo Xcode — uma limitação de ambiente local (sem Apple Developer Team configurado), não do código. Ao abrir o projeto em um Mac com uma conta de desenvolvedor configurada no Xcode, isso é resolvido automaticamente pelo "Automatically manage signing".

## Como executar

1. Abra `WorkLog.xcodeproj` no Xcode.
2. Selecione o scheme **WorkLog** e o destino **My Mac**.
3. Rode com `Cmd+R`. O app aparecerá apenas na Menu Bar (sem ícone no Dock).

## Como compilar (linha de comando)

```bash
xcodebuild -project WorkLog.xcodeproj -scheme WorkLog -configuration Debug -destination 'platform=macOS' build
```

## Como rodar os testes

```bash
xcodebuild -project WorkLog.xcodeproj -scheme WorkLog -destination 'platform=macOS' test -only-testing:WorkLogTests
```

## Como gerar um Release

```bash
xcodebuild -project WorkLog.xcodeproj -scheme WorkLog -configuration Release -destination 'platform=macOS' archive -archivePath build/WorkLog.xcarchive
```

Ou, no Xcode: **Product → Archive**, depois **Distribute App → Copy App** (ou o método de distribuição desejado) no Organizer.
