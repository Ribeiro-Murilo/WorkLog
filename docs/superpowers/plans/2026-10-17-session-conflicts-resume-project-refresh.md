# Conflitos de horário, retomada e atualização de projetos

> **Status:** aprovado pelo Murilo em 2026-10-17, com um commit separado por correção.
> **For agentic workers:** usar superpowers:subagent-driven-development na execução após aprovação. Dividir responsabilidades entre conflitos, retomada e atualização da lista; preservar alterações de outros agentes.

**Goal:** informar conflitos no lançamento manual, oferecer horário livre, permitir continuar apenas timers pausados e atualizar a aba Projetos após cadastro.

**Architecture:** preservar SwiftUI/MVVM, SwiftData e repositórios existentes. Regras de conflito e retomada ficam nas camadas de serviço/repositório; ViewModels apresentam o estado e Views oferecem as ações.

**Tech Stack:** Swift, SwiftUI, SwiftData, Swift Testing, Xcode.

**Spec:** requisitos e decisões deste documento, aprovados pelo Murilo.

## Regras aplicáveis

- Trabalhar na branch atual `main`; não criar branch ou PR, pois não foram solicitados.
- Preservar todas as alterações locais existentes, inclusive o redesign do Notch.
- Existe apenas um timer em execução. Trocar de projeto mantém a auto-pausa existente.
- Retomar inicia um novo intervalo a partir do momento atual; preserva o intervalo anterior e não contabiliza a pausa.
- Não retomar sessão concluída, sessão em execução ou projeto arquivado. Uma retomada contextual só fica disponível se o registro mais recente daquele projeto estiver pausado; encerrar o intervalo seguinte não deve oferecer retomada de uma pausa histórica anterior.
- O comando global Continuar só considera a última sessão global e exige que esteja pausada; não procura pausas antigas depois de um encerramento.
- Conflitos consideram todos os projetos. Horários adjacentes são permitidos. Edição ignora o próprio registro; sessão em execução ocupa desde seu início até ser fechada.
- Sugestão preserva a duração e busca o intervalo livre mais próximo no mesmo dia do início informado, preferindo o posterior em empate. Se não couber no dia, informar a ausência de opção.
- Aplicar sugestão exige clicar em “Usar horário sugerido”; revalidar antes de salvar. Não alterar registros existentes para abrir espaço.
- Manter Data e início/fim coerentes no formulário manual, preservando a duração ao trocar o dia.
- Projeto novo aparece imediatamente se corresponder à busca e aos filtros atuais; cancelamento ou falha não dispara uma criação.

## Plano de execução

### 1. Conflitos e sugestão de horário

**Arquivos:** `WorkLog/Repositories/SessionRepository.swift`, `WorkLog/Services/ValidationService.swift` ou serviço específico de disponibilidade, `WorkLog/ViewModels/SessionFormViewModel.swift`, `WorkLog/Timer/SessionFormView.swift`; testes de repositório, disponibilidade e formulário.

- [x] Criar testes de sobreposição entre projetos, exclusão do próprio registro, limites adjacentes, meia-noite e timer em execução.
- [x] Expor os registros conflitantes com projeto, data e intervalo, mantendo a validação ao salvar.
- [x] Calcular lacunas por interseção real dos intervalos com o dia; não usar a consulta que filtra apenas a data de início.
- [x] Testar a sugestão mais próxima, desempate posterior, preservação da duração e ausência de espaço.
- [x] Mostrar conflitos e sugestão no formulário, atualizar quando projeto/horários mudarem e oferecer aplicação explícita.
- [x] Alinhar o campo Data aos horários e verificar a aplicação da sugestão sem salvar automaticamente.

### 2. Continuar timer pausado

**Arquivos:** `WorkLog/Services/TimerService.swift`, `WorkLog/Repositories/SessionRepository.swift`, ViewModels e controles de menu/detalhe de projeto; integrar com a proteção já existente no Notch sem substituir seu redesign. Testes em `WorkLogTests/TimerServiceTests.swift` e ViewModels pertinentes.

- [x] Criar testes que revelem a retomada indevida de sessão concluída e a falta de retomada contextual.
- [x] Centralizar elegibilidade no serviço, consultando o estado persistido e a sessão mais recente pertinente.
- [x] Expor Continuar para pausa elegível nos controles existentes e Retomar no detalhe do projeto; ocultar/desabilitar para encerrados.
- [x] Preservar a auto-pausa ao trocar de projeto e impedir que o comando global reinicie um timer já em execução.
- [x] Testar exclusão do tempo de pausa, timer único, projeto arquivado, reconstrução do serviço após reabrir e impossibilidade de ressuscitar pausa antiga após encerramento.

### 3. Atualização imediata da aba Projetos

**Arquivos:** `WorkLog/Projects/ProjectListView.swift`; testes de ViewModel ou verificação dirigida do fluxo existente.

- [x] Ligar o callback `onSaved` já oferecido por `ProjectFormView` ao `reload()` da lista.
- [x] Verificar cadastro com a aba aberta, preservando busca, filtros e ordenação.
- [x] Verificar cancelamento e formulário inválido sem alterações na lista.

## Validação e revisão

- [x] Rodar os testes focados durante cada tarefa e a suíte unitária ao integrar: `xcodebuild -project WorkLog.xcodeproj -scheme WorkLog -destination 'platform=macOS' test -only-testing:WorkLogTests`.
- [x] Compilar o app e inspecionar capturas sintéticas do Form de conflitos e dos estados pausado/idle do Notch. Cadastro: callback e caminhos de sucesso/erro/cancelamento/filtros revisados; não houve teste manual completo de navegação/rolagem do sheet nem do cadastro no app aberto.
- [x] Revisão final independente aprovada, preservando as alterações anteriores e conferindo integração de menu, atalhos e Notch.
- [x] Informar resultado dos testes e eventuais limites reais de validação. Publicação/release não faz parte desta tarefa.

## Review Focus

- Outra sessão pode mudar entre a sugestão e Salvar: revalidação deve impedir sobreposição.
- Intervalos iniciados em outro dia também bloqueiam o trecho ocupado no dia escolhido.
- Encerrar um intervalo retomado não torna uma pausa anterior daquele projeto retomável.
- Projeto criado fora da busca/filtro atual não deve aparecer artificialmente na lista filtrada.
- Integração com Notch deve preservar suas alterações locais e a mesma regra de elegibilidade do serviço.

## Evidência de execução

- Cadastro corrigido em `c3f4459`, revisão independente aprovada e build Debug concluído.
- Conflitos implementados em `859f9ac`, revisão independente aprovada e 13 testes focados passando, incluindo captura opcional.
- Retomada: RED reproduziu 6 regressões; GREEN executou 28 testes focados com captura do Notch. Revisão identificou invalidação ausente do botão após inserção/exclusão de sessões; adicionada revisão observável no repositório e teste real de Observation (RED com 4 falhas; GREEN com 31 testes). Segunda revisão aprovou a correção.
- Integração: `xcodebuild -project WorkLog.xcodeproj -scheme WorkLog -destination 'platform=macOS' -derivedDataPath /tmp/worklog-integrated-validation test -only-testing:WorkLogTests` terminou com `TEST SUCCEEDED`, 144 testes em 24 suítes. Os dois testes opcionais de captura foram ignorados nessa rodada e executados com as respectivas variáveis de ambiente nas rodadas focadas.
- Há avisos preexistentes da toolchain (isolamento MainActor, capturas concorrentes e Info.plist em recursos) e mensagens de serviços do macOS/CoreSimulator; não houve falha na suíte macOS.
- Revisão final agregada aprovada, sem findings introduzidos. Cache do Notch fixado para alterações externas permanece com atualização por eventos existente e revalidação no clique; não houve ampliação desse comportamento preexistente.
