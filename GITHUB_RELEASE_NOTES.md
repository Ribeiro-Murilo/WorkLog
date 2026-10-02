# WorkLog 0.1.7

## Correção da abertura do painel no notch

- Corrigida a perda da referência à tela que podia deixar o painel visível, mas sem expandir ao passar o mouse, até reiniciar o WorkLog.
- Recuperação da apresentação após suspensão, despertar das telas e desbloqueio, inclusive quando o monitor ainda está temporariamente indisponível.
- Animações de abertura, fechamento e largura do timer usam a geometria atual da tela ao concluir, evitando restaurar uma posição antiga.
- Preservados o primeiro clique, a área segura da câmera, o badge do timer e o fallback para a barra de menu.

## Validação

107 testes automatizados passaram com telas e notificações simuladas. A falha intermitente na sessão real não foi reproduzida. O pacote é universal para Intel e Apple Silicon, com atualização assinada para o Sparkle.
