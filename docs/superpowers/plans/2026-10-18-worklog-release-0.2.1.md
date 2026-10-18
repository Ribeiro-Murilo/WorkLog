# Release WorkLog 0.2.1

**Status:** usuário testou a correção e aprovou explicitamente a publicação em 18/10/2026.
**Objetivo:** publicar versão 0.2.1/build 13 com os commits de retomada da mesma sessão e visualização/edição dos ciclos.

## Regras
- Trabalhar na main atual; sem branch/PR; preservar commits separados, autoria de Murilo e ausência de coautoria.
- Build 13 posterior à versão pública build 10 e ao teste local build 12; manter bundle ID, feed, chave Sparkle e requisito macOS.
- Gerar archive universal e ZIP em build/release-0.2.1, preservando os artefatos anteriores, dados e app local aberto.
- Manter assinatura de distribuição existente; não exportar chave privada nem alterar configuração de segurança.
- Não substituir tags nem forçar push. Confirmar asset público antes de enviar o appcast à main.

## Passos
- [x] Conferir HEAD e remoto: main pública d546c1b, release pública v0.2.0, v0.2.1 inexistente.
- [x] Preparar versão/build e notas; código funcional permanece igual ao aprovado no build 12.
- [x] Gerar archive Release universal, ZIP e assinatura Sparkle; verificar versão, arquiteturas e assinatura.
- [ ] Gerar e revisar appcast, tamanho, digest e chave pública; commit de release e tag.
- [ ] Enviar tag, criar draft e conferir asset remoto; publicar release antes de main/feed.
- [ ] Confirmar release, download, digest, tag/commit, main remota e feed público.

## Validação
- Código aprovado: 174 testes em 27 suítes e build Debug do ciclo anterior; logs /tmp/worklog-cycle-final-tests.log e build/local-test-cycles-2026-10-18/build.log.
- Usuário testou e aprovou a UI em 18/10/2026.
- Verificação do pacote e publicação será registrada em build/release-0.2.1/verification.json e publication.json.

## Evidência do pacote
- Archive Release universal compilou com sucesso. Versão 0.2.1/build 13, arquiteturas arm64 e x86_64.
- ZIP de 8.302.214 bytes, SHA-256 f2aa549370a407e71275760f1399197557d6f74f8675c38e4c52e2f4dae138b0.
- Assinatura do archive e do bundle extraído verificadas; conteúdo e permissões do ZIP correspondem ao archive.
- Assinatura Sparkle verificada com sign_update e CryptoKit usando a chave pública embarcada. Feed XML preserva as entradas anteriores e adiciona uma única entrada build 13 com tamanho e assinatura corretos.
- Distribuição ad hoc existente preservada, sem notarização Apple; dados locais e instalação não alterados.
- A publicação será registrada em build/release-0.2.1/publication.json após este commit, preservando a correspondência do tag com o pacote.
