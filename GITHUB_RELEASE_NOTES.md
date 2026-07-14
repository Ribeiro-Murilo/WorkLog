## O que mudou

- aceita o primeiro clique no conteúdo SwiftUI do notch após troca de foco
- torna o painel `key` somente na transição normal de recolhido para expandido
- mantém o estado visual controlado exclusivamente pela posição do mouse
- remove callbacks tardios de animação que podiam restaurar frames antigos de hit-testing
- mantém o hosting view sincronizado com o tamanho do painel por autoresizing

## Causa raiz

O painel podia continuar visualmente expandido depois de perder o estado de `key window`, enquanto completions de animações anteriores podiam aplicar frames obsoletos à área clicável. A tentativa inicial de recuperar foco continuamente também criou um ciclo de expandir/recolher sobre a área física do notch; agora a perda de foco não altera `isExpanded`, evitando o piscar.

## Impacto

Os botões do notch continuam respondendo após sessões longas, troca de aplicativo, Space e sleep/wake, sem exigir parar o timer ou reiniciar o WorkLog.

## Validação

- `git diff --check`
- `TimerServiceTests`: 7/7 passaram
- `NotchWindowController.swift` compilou sem os avisos de concorrência anteriores
- revisão paralela do comportamento AppKit sem bloqueadores

O build global permanece bloqueado por um erro preexistente em `ReportsView.swift:73`: `Project?` é usado em um `Picker` sem conformidade `Hashable`.
