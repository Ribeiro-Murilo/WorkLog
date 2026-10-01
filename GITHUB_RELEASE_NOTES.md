# WorkLog 0.1.6

## Sincronização entre Macs pelo iCloud Drive

Agora é possível sincronizar projetos, sessões pausadas ou encerradas, comentários, faturas, presets de relatório e dados do emissor usando uma pasta comum do iCloud Drive. Não é necessária uma assinatura do Apple Developer Program.

1. Ative o iCloud Drive nos dois Macs com a mesma conta Apple.
2. Abra **Configurações → Sincronização** no WorkLog e escolha uma pasta no iCloud Drive.
3. No outro Mac, selecione a mesma pasta. O WorkLog cria a subpasta `WorkLog Sync` para guardar o histórico de alterações.

- A verificação ocorre automaticamente enquanto o aplicativo está aberto; **Verificar agora** permite iniciar uma verificação local.
- Você pode continuar trabalhando offline. As alterações são combinadas quando a pasta volta a ficar disponível e os arquivos chegam pelo iCloud.
- Edições concorrentes aparecem como conflitos, com escolha da versão a manter. Faturas com números repetidos permitem atribuir um novo número.
- Cronômetros em execução permanecem locais até a sessão ser pausada ou encerrada. Preferências de cada Mac e atalhos também permanecem locais.
- Alterar a pasta ou desativar a sincronização preserva os dados e os arquivos anteriores.

## Outras melhorias

- Backup completo em JSON, incluindo comentários, faturas, presets, configurações e atalhos, com importação compatível com os backups antigos.
- Painel mais compacto na barra de menus e no notch.
- Migração do armazenamento legado quando o armazenamento atual está vazio, preservando o banco original e avisando quando ambos já contêm dados.

## Limite da validação

O transporte real pelo iCloud Drive entre dois Macs ainda não foi validado. Uma verificação local concluída não confirma que o outro Mac recebeu os arquivos; o iCloud pode levar algum tempo para transportá-los.
