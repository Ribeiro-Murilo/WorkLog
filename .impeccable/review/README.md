# Verificação nativa do painel

Capturas NSHostingView fora da tela, com dados sintéticos, geradas por WorkLogTests/NotchPanelRenderingTests.swift. Não são capturas do desktop do usuário e não exigem iniciar WorkLog.app. O fundo azul acinzentado e as margens laterais são contexto da captura para mostrar a transparência e as curvas; não fazem parte do painel.

Arquivos: notch-running.png, notch-paused.png, notch-idle.png, notch-search-empty.png e notch-long-content.png. A câmera tem reserva de 32 pontos no cenário simulado. Largura do painel: 368 pontos; corpo: 340 pontos.

Validação: 123 testes em 22 suites passaram, incluindo a renderização opcional ativada por WORKLOG_NOTCH_PREVIEW_DIR. Xcode Debug build passou sem assinatura, em /tmp/worklog-notch-build. Nenhum pacote foi publicado ou instalado.

Comando de regeneração: WORKLOG_NOTCH_PREVIEW_DIR="$PWD/.impeccable/review" scripts/test-headless.sh --filter NotchPanelRenderingTests
