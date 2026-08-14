# WorkLog: migração do armazenamento legado

## Contexto

O WorkLog passou de App Sandbox ativado para `ENABLE_APP_SANDBOX = NO` quando o
Sparkle foi adicionado. O SwiftData usa o caminho padrão do processo, então a
versão instalada passou a abrir:

`~/Library/Application Support/default.store`

Os dados antigos permaneceram em:

`~/Library/Containers/RibeiroWorkes.WorkLog/Data/Library/Application Support/default.store`

O banco novo contém apenas configurações iniciais. O banco legado contém os
registros do usuário e deve ser tratado como fonte preservada durante a
migração.

## Objetivo

Na primeira inicialização em que o banco atual estiver vazio e o banco legado
contiver dados, migrar todos os dados persistidos para o banco atual, mantendo
IDs, datas, valores, configurações e relacionamentos. A migração deve ser
idempotente, não apagar o banco legado e não sobrescrever dados já existentes.

## Fora de escopo

- Reativar o App Sandbox.
- Alterar o fluxo de atualização do Sparkle.
- Apagar, mover ou compactar o banco legado.
- Fazer merge automático quando os dois bancos já contiverem dados.
- Migrar bancos de outras versões, usuários ou bundles sem o mesmo
  identificador (`RibeiroWorkes.WorkLog`).

## Abordagens consideradas

### Migração automática no app — escolhida

O `PersistenceController` mantém o banco atual como destino e abre o banco
legado em um segundo `ModelContainer`, somente para leitura. Um serviço de
migração copia valores para novos objetos do destino e reconstrói os
relacionamentos por ID. O app continua usando apenas o banco atual depois da
migração.

Essa abordagem é repetível, pode ser testada com bancos temporários e resolve
também futuras instalações que ainda encontrem o mesmo banco legado.

### Reativar o App Sandbox

Faria o app voltar ao caminho antigo, mas conflita com a configuração escolhida
para o Sparkle e não oferece uma migração para instalações já sem Sandbox.

### Cópia manual do arquivo

É menor em código, mas é sensível ao estado dos arquivos `-wal`/`-shm`, não
trata conflitos e deixa o problema sem correção para o próximo usuário ou
instalação.

## Desenho técnico

### Descoberta e decisão

1. Criar o `ModelContainer` de destino usando a configuração padrão atual.
2. Procurar o arquivo legado no caminho fixo derivado da home do usuário e do
   bundle ID.
3. Considerar o destino vazio quando ele tiver apenas a configuração padrão
   criada por `SettingsRepository.current()` e atalhos padrão criados por
   `ShortcutsService`, sem projetos, sessões, comentários, presets ou faturas.
   Essas linhas iniciais serão atualizadas com os valores do legado, em vez de
   criar duplicatas.
4. Considerar o legado migrável quando houver qualquer dado de usuário.
5. Se o destino estiver vazio e o legado for migrável, iniciar a migração.
6. Se ambos tiverem dados, não fazer merge silencioso; manter o destino e
   registrar uma notificação de conflito.
7. Se o legado não existir, continuar normalmente sem migração.

O estado de conclusão será registrado somente depois de um `save()` bem-sucedido
no destino, usando a chave `WorkLog.storageMigration.v1.completed` em
`UserDefaults`. A decisão também verificará se o destino ainda contém dados
antes de repetir uma migração marcada, para que o mecanismo continue seguro em
um reset legítimo do banco.

### Dados migrados

Todas as entidades do schema atual serão contempladas:

- `Project`: preservar UUID, campos de negócio, datas, status e favoritos.
- `Session`: preservar UUID, horários, duração, nota, status e referência ao
  projeto correspondente.
- `Comment`: preservar UUID, texto, autor, data e referência ao projeto.
- `AppSettings`: copiar preferências e contador de faturas para a configuração
  existente no destino quando ela for apenas a configuração inicial.
- `ShortcutBinding`: copiar ação, combinação de teclas, habilitação e data de
  atualização; a ação é a chave natural porque esse modelo não possui UUID.
- `ReportPreset`: preservar UUID, nome, colunas, agrupamento e datas.
- `Invoice`: preservar UUID, número, cliente, período, itens congelados, total,
  status, observações e datas.

Projetos serão criados primeiro e indexados por UUID. Sessões e comentários
serão criados depois usando esse índice, evitando relacionamentos quebrados.
Faturas não dependem de projetos ou sessões porque seus itens são snapshots.

### Atomicidade e preservação

- O arquivo legado original nunca será aberto para escrita. Para permitir que
  o SwiftData faça qualquer atualização técnica necessária ao carregar um
  schema antigo, o arquivo e seus `-wal`/`-shm` serão copiados para uma pasta
  temporária; somente essa cópia poderá ser aberta com escrita.
- Os objetos transferidos serão preparados em um único contexto de destino.
- O contexto fará um único save transacional; em erro, fará rollback e não
  registrará a conclusão.
- O arquivo legado, seus arquivos auxiliares e seu conteúdo permanecerão no
  local original.
- Nenhum dado do destino será sobrescrito quando o destino já tiver dados.

### Avisos e falhas

O app continuará abrindo com o banco atual e exibirá um aviso de inicialização
quando ocorrer qualquer uma destas condições:

- os dois bancos contêm dados;
- o legado existe, mas não pôde ser aberto ou lido;
- a versão/schema do legado é incompatível;
- o save da migração falhou.

O aviso informará que o banco legado foi preservado e mostrará o caminho para
permitir uma decisão posterior. Não haverá exclusão automática nem tentativa
silenciosa de merge.

## Testes e critérios de aceite

Adicionar testes de migração com bancos temporários contendo:

1. todas as entidades e relacionamentos, verificando contagens, IDs e valores;
2. destino vazio com sucesso e marcador de conclusão;
3. segunda execução sem duplicar registros;
4. destino com dados, verificando que nenhuma escrita ocorre e há notificação;
5. legado ausente, verificando inicialização normal;
6. falha de leitura ou save, verificando rollback, ausência de marcador e
   preservação da fonte;
7. configuração e atalhos, incluindo o contador de faturas.

Os testes existentes devem continuar passando. A validação final no ambiente do
usuário será feita com o app fechado quando necessário, confirmando que os
registros do banco legado aparecem no app e que o banco legado continua
presente.
