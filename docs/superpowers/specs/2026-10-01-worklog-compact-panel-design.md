# Painel compacto do WorkLog

Plano aprovado pelo usuário em 2026-10-01: ajustar a altura ao conteúdo, alinhar ao topo abaixo da câmera, reduzir espaçamentos e manter projetos roláveis com rodapé visível.

O painel continua nativo macOS, com largura de 340 pontos no notch e conteúdo de 320 pontos. A altura expandida vem da medição intrínseca do conteúdo, incluindo a área segura física da câmera. A medição não pode depender da altura imposta pelo próprio painel. A lista ocupa somente sua altura real até o limite de 175 pontos.

Usar margens de 12 pontos, intervalos de 4/8/12 e linhas de ações de 32 pontos. Preservar marca, textos e ações. Nomes longos permanecem em uma linha com truncamento.

Regras preservadas: uma sessão em execução; continuar retoma o último projeto; pausar e encerrar mantêm seus estados atuais; favoritos, recentes e total diário mantêm a origem de dados. Preservar safe area, badge colapsado, fallback à barra de menu, primeiro clique, foco e histerese de hover.

Validar compilação, testes existentes e renderização nativa da geometria. Verificar estados vazio, ativo, poucos/muitos projetos e textos longos em temas claro/escuro. Não publicar nem substituir a instalação do usuário.
