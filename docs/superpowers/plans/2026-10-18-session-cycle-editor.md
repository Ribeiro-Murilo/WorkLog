# Ver e editar os ciclos de uma sessão

**Status:** plano aprovado pelo usuário em 2026-10-18; implementar e abrir build local antes de publicar.
**Goal:** mostrar início/fim/duração de cada ciclo e permitir corrigir seus horários preservando a sessão e as pausas.
**Architecture:** usar os SessionWorkPeriod já persistidos. Linha expansível exibe os ciclos; o formulário existente oferece campos individuais para cada ciclo quando houver vários. ViewModel mantém rascunho isolado e valida antes de alterar a Session.
**Tech Stack:** SwiftUI nativo macOS, SwiftData, Swift Testing.
**Spec:** requisitos e decisões deste plano, aprovados na conversa.

## Regras
- Preservar UUID, quantidade de sessões, ordem e quantidade de ciclos e status pausada/concluída.
- Mostrar data, início, fim e duração. Ciclo aberto mostra Em andamento, sem fim inventado.
- Editar horários apenas com timer pausado ou encerrado. Nenhuma alteração no modelo ao digitar/cancelar.
- Fim posterior ao início; ciclos em ordem sem sobreposição; horários adjacentes permitidos; validar conflito com outros registros antes de salvar.
- Recalcular início/fim/data da sessão e total somando ciclos; pausas continuam excluídas. Rejeitar rascunho obsoleto se ciclos mudaram ou sessão foi removida/retomada.
- Cadastro manual e edição de um único intervalo preservam fluxo atual. Sem criação/exclusão de ciclos, fusão de registros ou mudança de sync nesta tarefa.
- UI nativa existente, sem redesign do Notch. Trabalhar na main, commit de Murilo sem coautoria, não criar branch/PR nem publicar release/tag/feed.

## Contrato
- SessionFormViewModel usa `private(set) var cyclePeriods: [SessionWorkPeriod]`, `usesCycleEditor: Bool` (edição com vários ciclos), `cyclesTotal: TimeInterval`, `cycleValidationMessage: String?` e métodos `updateCycleStart(at: Int, to: Date)` / `updateCycleEnd(at: Int, to: Date)`.
- `isTimeEditingLocked` passa a bloquear somente sessão em execução; formulário de múltiplos ciclos usa rascunho em cyclePeriods, sem editar o envelope geral.
- SessionRowView recebe `onEditCycles: (() -> Void)? = nil`; disclosure nativo exibe todos os ciclos, botão Editar ciclos quando callback existir e sessão não estiver executando. Projeto liga ao sheet existente, Dashboard usa a leitura sem callback.

## Tarefas
- [x] Lógica: escrever e observar falha de teste de edição de dois ciclos que preserva UUID e recalcula total; implementar rascunho, validação interna/externa, datas e proteção contra mudanças concorrentes. Dono: agente lógica, SessionFormViewModel.swift e SessionRepositoryTests.swift/novo teste dedicado.
- [x] UI: DisclosureGroup com data/hora com segundos, início/fim/duração de cada ciclo e estado aberto; formulário com seções Ciclo N e DatePickers nativos, total e erro claro. Dono: agente UI, SessionRowView.swift, ProjectDetailView.swift, SessionFormView.swift e teste de captura sintética próprio.
- [x] Executar suíte headless e build Xcode; revisão independente; inspecionar UI com dados sintéticos sem gravar no banco real.
- [x] Salvar backup consistente, encerrar build anterior normalmente e abrir novo build local. Conferir caminho/versão do processo e tela aberta. Commit da mudança, entregar roteiro e aguardar teste do usuário antes da release.

## Review Focus
- Editar o ciclo do meio não modifica vizinhos, não une pausas e não cria outra sessão.
- Conflitos internos/externos falham sem alterar dados; adjacência e intervalo de pausa continuam válidos.
- Reabertura e retomada após edição preservam duração/status; ciclo ativo não aceita alteração.
- Draft obsoleto não apaga um ciclo criado por uma retomada em outra superfície.
- Datas atravessando meia-noite e ciclos curtos continuam legíveis; controles acessíveis em português e form rolável.

## Evidências
- RED: `/tmp/worklog-cycle-red.log`, edição multiciclo antes bloqueada.
- GREEN: 174 testes em 27 suítes; `/tmp/worklog-cycle-final-tests.log`. Captura sintética reconfirmada em `/tmp/worklog-cycle-preview-confirm.log`.
- Xcode Debug 0.2.1/build 12 compilou; assinatura local verificada com codesign deep/strict.
- Revisão independente sem achados acionáveis. UI real conferida: expansão dos três ciclos, campos com segundos, erro ao criar rascunho inválido e cancelamento.
- Backup consistente anterior à abertura em `build/local-test-cycles-2026-10-18/before-launch.store`. Dados de negócio das 25 sessões e 3 projetos preservados; apenas metadado interno Z_OPT mudou.
- App local aberto pelo caminho explícito de build 12; publicação permanece pendente do teste do usuário.
