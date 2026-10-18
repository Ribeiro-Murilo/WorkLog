# Notch Panel Implementation Plan

> **For agentic workers:** Implementar tarefas independentes em paralelo, preservando alterações existentes. A execução foi explicitamente autorizada pelo usuário na conversa.

**Goal:** Implementar no notch o visual aprovado com curvas superiores côncavas.

**Architecture:** Conteúdo SwiftUI exclusivo do notch e ViewModel com repositórios/TimerService existentes. Contorno e conteúdo usam dimensões compartilhadas; fixação chega ao controlador via DisplayModeManager.

**Tech Stack:** SwiftUI, AppKit, Observation, SwiftData, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-10-17-notch-panel-redesign.md`

## Global Constraints

- Branch atual; sem publicação, instalação, commits ou PRs.
- Preservar mudanças locais em NotchWindowController, NotchLifecycleObserver e seus testes.
- Um cronômetro ativo, retomada como novo intervalo, dados e sincronização intactos.
- Câmera livre; primeiro clique, hover e badge preservados.
- Verificação sem iniciar o aplicativo ou operar o desktop do usuário.

## Review Focus

- Ombros realmente côncavos e dentro dos limites da janela, sem recortar conteúdo.
- Busca com acentos, muitos projetos, nomes longos e nenhum resultado.
- Estado pausado distinguível de encerrado e erro de persistência visível.
- Saída do cursor com painel fixado; desfazer fixação e modo de exibição.
- Lista pequena/grande e configurações de segundos sem esconder controles.

## Task 1 — contorno, janela e integração (agente principal)

- [x] Testar forma com ombros côncavos, origem deslocada e dimensões pequenas; observar falha antes de implementar.
- [x] Implementar NotchPanelMetrics e NotchShape sem alterar o contorno colapsado.
- [x] Ajustar fundo escuro, largura e medição intrínseca do NotchContentView.
- [x] Integrar fixação e política de hover mantendo mudanças locais.
- [x] Conectar novo conteúdo ao WorkLogApp; compartilhar registro de atalhos.

## Task 2 — conteúdo e ViewModel (worker notch_panel)

- [x] Criar NotchPanelView, NotchPanelStyle e NotchPanelViewModel.
- [x] Implementar busca, deduplicação, estados e erros com serviços existentes.
- [x] Testar comportamento dos projetos, busca, sessões e total fechado.

## Task 3 — verificação e documentação (agente principal + revisão)

- [x] Registrar novos testes no projeto Xcode.
- [x] Executar a suíte headless SwiftPM e xcodebuild build; confirmar resultados.
- [x] Capturar conteúdo nativo fora da tela em estados ativo, pausado e vazio, com dados sintéticos.
- [x] Revisão independente da referência e capturas; corrigir achados materiais em lote.
- [x] Documentar o visual entregue em DESIGN.md e .impeccable/design.json.

## Resultado da verificação

- 123 testes em 22 suítes passaram; build Debug Xcode concluído.
- Cinco estados capturados em SwiftUI/AppKit fora da tela; nenhuma interação com o desktop ou execução do app principal.
- Revisões independentes concluídas. Corrigidos retomada de projeto arquivado, revalidação da última sessão, preferência de segundos e divisórias.
- Recomendação estética remanescente da revisão: retirar o label de estado acima do projeto. Mantido por decisão do agente principal para cumprir a composição expressamente aprovada pelo usuário; instrução do usuário prevalece sobre a regra estética da skill. A revisão manteve disposition `fix` por esse único ponto.
- Não houve comp-diff automatizado; nenhum score numérico ou passe de ferramenta foi declarado.
