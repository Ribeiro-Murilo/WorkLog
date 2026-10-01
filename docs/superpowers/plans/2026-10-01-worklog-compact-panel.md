# WorkLog Compact Panel Implementation Plan

**Goal:** Remover espaços vazios do painel preservando seu uso como utilitário nativo.

**Architecture:** SwiftUI mede o conteúdo intrínseco expandido e informa sua altura ao controlador AppKit. O controlador atualiza o frame ancorado ao topo sem reconstruir a view. O popover limita a lista à altura real com rolagem acima de 175 pontos.

**Tech Stack:** SwiftUI, AppKit, Observation.

**Spec:** `docs/superpowers/specs/2026-10-01-worklog-compact-panel-design.md`

## Constraints

- Trabalhar na branch atual; autorização recebida após apresentação do plano.
- Preservar timer, persistência, textos, atalhos, foco, hover e safe area física.
- Não modificar componentes globais fora do painel.

## Tasks

- [x] Compactar `MenuBarPopoverView.swift`: padding12, gap8, ações32, truncamento e lista com altura real limitada175.
- [x] Em `NotchContentView.swift`, alinhar no topo e medir conteúdo com altura intrínseca incluindo safe area; informar `onExpandedHeightChange(CGFloat)`.
- [x] Em `NotchWindowController.swift`, implementar `updateExpandedHeight(_:)`, filtrando medidas inválidas/repetidas, atualizando frame sem refreshContent; conectar em `DisplayModeManager.swift`.
- [x] Compilar, executar testes existentes, verificar geometria com renderização nativa e revisar diff com agente independente.

## Review focus

- Lista curta deve encolher, lista longa rolar com rodapé acessível.
- Mudanças do timer/lista devem atualizar a altura sem loop de medição.
- Medição não pode usar altura do wrapper expandido.
- Câmera permanece livre; conteúdo começa logo abaixo dela.
- Primeiro clique, foco e regiões de hover preservados.

## Decisions

Mudanças visuais reversíveis serão verificadas por renderização e build; não adicionar testes que apenas repitam os valores de padding. Usar harness temporário para exercitar a integração SwiftUI/AppKit e testes existentes para regras de negócio. Sem commit/publicação automático.

## Validation results

- Build/test: `xcodebuild -project WorkLog.xcodeproj -scheme WorkLog -configuration Debug -destination 'platform=macOS' -derivedDataPath /tmp/worklog-compact-build test -only-testing:WorkLogTests`: 44 testes em 9 suites passaram.
- Harness AppKit/SwiftUI: conteúdo220 + câmera32 mediu252, alinhado em y32 (antes y116 no painel420). Mudança para conteúdo300 mediu332 sem recriar view; claro/escuro verificados nas fixtures técnicas.
- Revisão independente reproduziu conflito da animação antiga com resize. Corrigido deferindo aplicação da altura até completionHandler com identificador de transição e MainActor; probe confirmou altura final estável.
- Build inicial e cópia de HEAD reproduziram erro preexistente de `Project?` sem `Hashable` no Picker de relatórios. Usar UUID como seleção resolveu preservando o filtro por projeto.
- Capturas do painel completo não puderam ser obtidas: `DependencyContainer.preview()` falhou em SwiftData/`SessionRepository.fetchActiveSession` antes de montar a view, tanto no harness isolado quanto no teste visual temporário. Teste temporário restaurado byte por byte; os 44 testes existentes permanecem com evidência de aprovação. Estados completos com listas e timer precisam de inspeção manual no build.
- Detector layout sem achados e `git diff --check` limpo. Build local disponível em `build/WorkLog-compact.app`, assinatura verificada; instalação atual preservada.
