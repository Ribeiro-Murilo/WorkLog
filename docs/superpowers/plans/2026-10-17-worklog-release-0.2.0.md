# Release WorkLog 0.2.0

**Status:** usuário aprovou execução e publicação da release 0.2 em 2026-10-17. A versão foi normalizada como 0.2.0, tag v0.2.0, build 10. Não requer nova aprovação para os passos autorizados.

**Goal:** publicar WorkLog 0.2.0 / build 10 no GitHub e disponibilizar a atualização pelo Sparkle.

**Architecture:** manter a distribuição existente por ZIP e appcast assinado; gerar archive Release universal em pasta exclusiva. Publicar o asset antes de enviar o novo appcast à main remota.

**Tech Stack:** Xcode, Swift, Sparkle/EdDSA, Git e GitHub CLI.

## Regras e limites

- Trabalhar na branch atual main, sem criar branch ou PR.
- Preservar os commits separados das três correções e criar um commit próprio de release com metadados, notas e feed.
- Autoria de Murilo Ribeiro, sem Co-Authored-By.
- Versão aprovada 0.2.0, build 10, posteriores à release pública 0.1.7/build 9.
- Preservar bundle ID, chave pública e URL do feed, requisito macOS e configuração de distribuição existentes.
- Preservar artefatos em build/; usar build/release-0.2.0. Não executar o trecho de limpeza global de scripts/release.sh.
- Não alterar funcionalidades, dados locais ou instalação do aplicativo.
- Não substituir tags existentes, nem usar force push.
- Só publicar main/appcast após confirmar o ZIP acessível na release pública.

## Conteúdo das notas

- Lançamento manual informa conflitos e sugere horário livre mantendo a duração.
- Continuação somente de timers pausados, sem contabilizar o período de pausa.
- Atualização imediata da lista após criar projeto.
- Novo painel do Notch e correção do hover sobre apps em tela cheia.
- Correção do crash de acessibilidade ao trocar abas das configurações.

## Execução

- [x] Revalidar HEAD, remoto main e inexistência da tag/release v0.2.0 antes de modificar/publicar.
- [x] Atualizar versão/build e preparar notas; manter escopo exatamente nos commits aprovados e nos metadados de release.
- [x] Gerar archive Release universal e ZIP WorkLog-0.2.0.zip em build/release-0.2.0.
- [x] Conferir versão/build, Intel + Apple Silicon, integridade da assinatura do app e do ZIP; assinar a atualização via chave existente no Keychain e verificar com a chave pública embarcada, sem exportar segredos.
- [x] Gerar entrada única no appcast com build 10, tamanho real, assinatura e URL definitiva; validar XML, URL e monotonicidade em relação ao feed remoto.
- [ ] Revisar pacote e metadados, criar commit de release e tag v0.2.0 no commit correspondente.
- [ ] Enviar a tag e criar release com ZIP inicialmente em draft; conferir asset remoto e digest contra SHA-256 local antes de publicar.
- [ ] Publicar a release; confirmar download público antes de enviar main e o novo feed.
- [ ] Confirmar release, tag/commit, tamanho/digest do asset, main remota e feed público; entregar link ao usuário.

## Evidência já disponível e validação restante

- Estado remoto consultado via GitHub CLI: última release pública v0.1.7 e main remota ef262a2; HEAD local 4d00a25. Conferir novamente na execução para evitar conflito com mudanças concorrentes.
- Código das correções validado nesta conversa: suíte completa passou com 144 testes em 24 suítes e compilação Debug incluída, log /tmp/worklog-integrated-final-tests.log. A preparação de release muda somente metadados; repetir testes apenas se houver mudança de código, falha ou outro motivo concreto.
- Archive Release universal gerado com sucesso em build/release-0.2.0/WorkLog.xcarchive. Bundle 0.2.0/build 10 com x86_64 e arm64, bundle ID, feed, chave pública e requisito macOS 26.5 preservados.
- ZIP validado independentemente: 8.228.019 bytes; SHA-256 bcb1c8988069bc2e29b22b0314ee40ee6f863844eb5292a5e6221e630de7698b. Extração idêntica ao archive; codesign --deep --strict passou nos dois bundles.
- Assinatura Sparkle gerada pelo signer com a chave existente no Keychain; sign_update --verify e verificação Ed25519 por CryptoKit com a chave pública embarcada passaram. Nenhuma chave privada foi lida ou exportada.
- Relatório completo: build/release-0.2.0/verification.json. Assinatura do app permanece ad hoc, sem Developer ID/notarização; não houve instalação nem execução do pacote.
- Appcast XML válido com uma entrada 0.2.0/build 10, assinatura e tamanho correspondentes ao ZIP; feed remoto anterior é idêntico ao histórico local e contém no máximo build 9.
- Etapas de publicação serão realizadas depois deste commit: tag, draft com asset conferido por digest, release pública e atualização de main/feed. A conferência final será registrada em build/release-0.2.0/publication.json para preservar o commit/tag do pacote.

## Review Focus

- Correspondência do ZIP com o commit/tag e versão/build corretos.
- Assinatura Sparkle validada com a chave pública do app.
- Asset público disponível antes da atualização do feed em main.
- Preservação dos artefatos anteriores e ausência de entrada/tag duplicadas.
