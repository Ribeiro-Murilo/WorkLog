## Correção dos cliques no notch

- recupera automaticamente a `key window` quando o painel expandido perde o foco enquanto o cursor ainda está sobre o notch;
- limita a recuperação de foco a uma vez a cada 250 ms, evitando disputa de foco e flicker durante animações, troca de Space ou wake/sleep;
- mantém o estado visual expandido até o cursor sair da área do notch, sem deixar o painel aberto e sem receber eventos;
- preserva o comportamento dos botões SwiftUI e não altera as regras do timer ou das sessões.

## Validação

- build Release do aplicativo;
- testes unitários do `WorkLogTests`;
- pacote `.zip` assinado para distribuição via Sparkle.
