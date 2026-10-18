---
version: 1
slug: "worklog-notch-notchpanelview-swift"
primary_target: "WorkLog/Notch/NotchPanelView.swift"
related_targets: ["WorkLog/Notch/NotchShape.swift","WorkLog/Notch/NotchContentView.swift"]
---

# Painel do notch

Modo Operate. Superfície nativa macOS para consultar/alternar a sessão sem abrir a janela principal. Escopo exclusivo do notch, câmera livre, timer único, sem mudanças em dados ou domínio. Prévia aprovada pelo usuário e autorizada para implementação em 2026-10-17: .impeccable/mocks/notch-approved.png. Os dados da imagem e das capturas são sintéticos.

## Direction contract

THESIS: controle imediato de uma sessão por projeto em um painel suspenso da borda física da tela, com conteúdo curto e ações claras.

OWN-WORLD: preto opaco integrado à câmera, textos brancos/cinza #A5A7AE, SF nativa, cronômetro monoespaçado de 42 pontos, controles grafite e acentos discretos de identificação por projeto.

STORY: reconhecer projeto e estado, pausar/encerrar/retomar, trocar projeto pela lista ou busca; consultar o total fechado do dia e abrir Dashboard/configurações.

FIRST VIEWPORT: ombros côncavos de 14 pontos inteiramente dentro da janela de 368 pontos; corpo de 340; safe area física da câmera antes do header; projeto/tempo/controles acima da busca; lista rolável limitada a 144 pontos; total e rodapé visíveis.

FORM: painel nativo aprovado em imagem pelo usuário, com curvas superiores revisadas por ele; autoridade é essa imagem, não uma direção aleatória. Identificador de aprovação: user-approved-notch-2026-10-17. Não houve concept-roll nem seed aleatória: direção fornecida e aprovada diretamente pelo usuário; este identificador não é seed de ferramenta.

FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, DESIGN.md, and every shipping raster carrying its provenance

## Verificação

Compilação Xcode, testes headless e capturas NSHostingView offscreen em estados ativo, pausado, vazio, sem resultados e nomes longos. Não há detector HTML/CSS para esta superfície nativa. Não iniciar WorkLog.app, operar o desktop, publicar ou instalar.

## Limite da evidência

As capturas nativas confirmam a implementação em pontos e foram comparadas visualmente por revisor independente. Não foram executadas as fases HTML/CSS comp-spec/build-phase/comp-diff; os registros em .impeccable/build são registros nativos manuais e não comprovantes desses gates. A imagem conceitual inclui ambiente e escala de apresentação diferentes. Não se declara reprodução pixel a pixel. O rótulo funcional de estado acima do projeto foi preservado por constar expressamente na referência e no escopo aprovados pelo usuário (brief wins).
