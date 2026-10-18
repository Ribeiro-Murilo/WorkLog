# Crash de acessibilidade nas configurações

## Escopo e regras

Corrigir a queda ao trocar abas das configurações, preservando dados, pasta configurada e regras do serviço de sincronização. Branch atual, sem commit, publicação ou instalação. A abertura do app de desenvolvimento e a navegação pelas abas foram autorizadas pela solicitação de teste e correção.

## Plano concluído

- [x] Ler o relatório e identificar a assinatura da falha.
- [x] Reproduzir o crash no app e isolar em uma interface com dados fictícios.
- [x] Aplicar a menor correção confirmada pelo experimento.
- [x] Compilar, executar a suíte existente e repetir a navegação real.

## Causa e correção

O relatório fornecido e a reprodução local em macOS 27.0.1 mostram stack overflow na consulta de `AccessibilityNode.accessibilityLabel`, com chamadas recursivas entre SwiftUI e AppKit. A reprodução mínima usou duas abas: um Form de configurações gerais e a FolderSyncSettingsView original com serviço fictício, caminho e última verificação presentes. Abrir a view isolada funcionou; Geral → Sincronização provocou o crash ao ler a árvore AX.

Remover somente o `accessibilityLabel` personalizado de `Text(path)`, mantendo seleção de texto e demais modificadores, eliminou a falha na reprodução. O caminho continua exposto na árvore AX dentro da seção Pasta compartilhada. Identidades explícitas por aba foram testadas sem sucesso e integralmente revertidas.

## Verificação

- Xcode Debug: BUILD SUCCEEDED (`/tmp/worklog-settings-fix-build.log`).
- Swift Testing: 123 testes em 22 suítes passaram (`/tmp/worklog-settings-fix-tests.log`). A suíte existente não reproduz a leitura AX externa; a regressão foi conferida no aplicativo real.
- Reprodução mínima corrigida: dois ciclos Geral ↔ Sincronização com leitura AX, sem crash, incluindo caminho selecionável e data de última verificação.
- App real corrigido: Sincronização → Geral → Sincronização → Atalhos → Faturamento → Backup → Sincronização → Atualizações → Sobre → Sincronização, com leitura AX após cada mudança, sem crash.
- Nenhum botão de alteração, sincronização, importação, exportação ou atualização foi acionado. A compilação de desenvolvimento mostra um erro de restauração do acesso à pasta; essa configuração foi preservada e não foi o objeto da correção.
