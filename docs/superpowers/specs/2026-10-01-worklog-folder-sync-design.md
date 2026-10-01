# WorkLog: sincronização por pasta no iCloud Drive

## Objetivo e autorização

Sincronizar automaticamente os dados entre Macs pela mesma pasta escolhida no
iCloud Drive, sem Apple Developer Program, CloudKit ou servidor. O usuário
aprovou o plano e autorizou iniciar o código em 2026-10-01. Trabalhar na branch
atual, sem criar branch ou PR e sem publicar versões.

## Arquitetura

Cada Mac mantém SwiftData local, explicitamente sem CloudKit. A pasta escolhida
contém um diretório `WorkLog Sync` com arquivos JSON imutáveis de operações.
Cada operação tem UUID, dispositivo, entidade/ID, versões ancestrais e dados
completos do registro ou uma exclusão. O app verifica a pasta periodicamente
enquanto aberto e permite verificar manualmente. O iCloud transporta arquivos;
o app combina registros. Não há garantia de envio instantâneo ou confirmação
de que outro Mac recebeu uma alteração.

O estado local de sincronização é armazenado numa entidade SwiftData exclusiva
desta máquina, junto das alterações importadas, no mesmo save transacional.
Operações locais são registradas antes de sua publicação, permitindo repetição
após falhas. Não copiar o banco SQLite ativo para uma pasta compartilhada.

## Regras

- Preservar UUIDs, datas, relacionamentos, valores e dados atuais.
- Sincronizar projetos, sessões encerradas/pausadas, comentários, faturas,
  presets e dados do emissor. Sessões em execução permanecem locais; passam a
  sincronizar quando pausadas/encerradas. Preferências de máquina e atalhos
  não são importados pela sincronização.
- Detectar diferenças locais antes de ingerir versões externas, para não
  sobrescrever edições feitas offline. Importação repetida é idempotente.
- Versões concorrentes diferentes ficam no histórico e são apresentadas como
  conflito. O usuário pode manter sua versão ou escolher outra; a resolução
  gera uma operação descendente de todas as versões conhecidas.
- Exclusões possuem operações próprias. Arquivos desaparecidos da pasta não
  significam exclusão de registros. Uma dependência ainda não recebida adia a
  aplicação; uma versão futura/inválida gera aviso e não apaga dados.
- Evitar excluir um projeto com cronômetro local ativo: pedir que ele seja
  pausado antes de aplicar a exclusão externa.
- Contador de faturas nunca diminui. Numerações repetidas são sinalizadas com
  opção de atribuir novo número a uma fatura, mantendo seus demais dados.
- Selecionar outra pasta inicia um novo estado de integração, preservando os
  dados locais e todos os arquivos da pasta anterior. Desativar não apaga nada.
- Os arquivos ficam na conta/pasta escolhida pelo usuário e usam sua cota de
  iCloud. Sem rede, espaço ou acesso à pasta, manter o banco local e tentar
  novamente. Bookmarks de pasta e estado da configuração são locais.
- Backup completo em JSON inclui todas as entidades de negócio, preferências
  e atalhos; continua aceitando o formato antigo. Importação não duplica UUIDs,
  preserva os relacionamentos e usa um único save transacional.

## Interface

Nova aba Sincronização nas configurações, com escolher pasta, caminho, estado,
última verificação local, verificar agora e desativar. Conflitos mostram versões
e ações de resolução. Colisões de faturas mostram opções de renumeração.
Explicar em linguagem simples que a mesma pasta deve ser escolhida nos Macs e
que o iCloud precisa estar ativo. Seguir Form e controles SwiftUI existentes.

## Validação

Testar operações concorrentes e sequenciais, exclusões, replay, dependências
fora de ordem, arquivos inválidos/versão futura, falhas de escrita, dados
completos, preferências locais, cronômetro ativo, contador e colisões de faturas,
backup antigo/novo e dois bancos locais ligados a uma pasta temporária.
Executar testes unitários completos e build Debug/Release. Um ensaio real do
transporte iCloud entre dois Macs depende desses dispositivos e será relatado
separadamente da simulação local. Os arquivos de histórico ficam retidos nesta
versão; não há compactação automática que possa remover versões ainda não
recebidas por um Mac offline.
