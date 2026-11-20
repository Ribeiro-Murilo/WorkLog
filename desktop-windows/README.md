# WorkLog para Windows (`desktop-windows`)

Port funcional do WorkLog (macOS SwiftUI v0.2.1) para Windows 10/11, mantendo a experiência de uso em segundo plano com a **barrinha superior estilo Notch** mais compacta horizontalmente.

## Destaques

- **Barrinha superior estilo Notch (compacta):**
  - **Parada / Pausada:** `112 × 18 px` (corpo central de `96 px` + ombros côncavos suaves de `8 px`), presa no topo central da tela com pontinho discreto.
  - **Com timer em execução:** `144 × 22 px` exibindo a bolinha com a cor determinística do projeto + tempo compacto (`MM:SS`, `H:MM:SS` ou `MM min`).
  - **Expandida ao passar o mouse ou clicar:** painel de `340 px` (`368 px` total com ombros côncavos), com botão Fixar (`Pin`), cronômetro em andamento/pausado (`Pausar`, `Encerrar`, `Retomar`), busca de projetos, troca rápida, total do dia e acesso ao Dashboard e Configurações.
  - **Alternativa na bandeja do sistema (Tray):** pode alternar entre barra superior e bandeja em **Configurações → Geral**.
- **Paridade completa com o macOS v0.2.1:**
  - **Resumo:** totais (Hoje, Semana, Mês, Total), projetos ativos/arquivados, últimas sessões (com ciclos expansíveis), mais utilizados e distribuições por categoria, cliente e projeto.
  - **Projetos:** busca, filtros (status, categoria, arquivados), ordenação, favoritos, comentários, criação/edição com validação de duplicidade e detalhe completo do projeto.
  - **Sessões e Ciclos:** retomada na mesma sessão (`workPeriods`), visualização e edição de múltiplos ciclos sem contabilizar pausas, detecção de conflitos e sugestão automática de horário livre mais próximo.
  - **Relatórios:** filtros completos, agrupamento detalhado ou por projeto+dia, seleção das 13 colunas, tipos de relatório salvos e exportação em **CSV**, **Excel (SpreadsheetML XML)** e **PDF**.
  - **Faturamento:** pré-visualização consolidada por cliente e período, bloqueio de sobreposição, numeração monotônica `FAT-0001`, status Pendente/Paga e PDF da nota.
  - **Backup compatível com macOS:** exportação e importação em JSON `formatVersion: 2` (incluindo datas Apple Reference Date, `workPeriodsData` em Base64) e importação de backups v1 legados.
  - **Recursos de sistema:** SQLite local nativo via `node:sqlite`, detecção de inatividade / bloqueio / suspensão, atalhos globais configuráveis e inicialização com o Windows.

## Desenvolvimento e Empacotamento

```bash
cd desktop-windows
npm install
npm test          # Testes unitários (Vitest)
npm run build     # Typecheck + build Electron/Vite
npm run dev       # Modo desenvolvimento (no Windows)
npm run dist:win  # Gera WorkLog-Setup-<versão>.exe (NSIS) e WorkLog-Portable-<versão>.exe no Windows
```

No GitHub Actions, o workflow [`.github/workflows/windows-desktop.yml`](../.github/workflows/windows-desktop.yml) valida os testes/build e gera automaticamente os instaladores `.exe` no runner `windows-latest`.
