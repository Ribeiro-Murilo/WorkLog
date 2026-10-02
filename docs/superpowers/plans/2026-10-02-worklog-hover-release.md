# Release WorkLog 0.1.7

Autorização do usuário em 2026-10-02: entregar uma nova release da correção do hover. Esta autorização amplia a tarefa anterior para commit, tag, publicação no GitHub e atualização do appcast do Sparkle. A instalação e a sessão macOS continuam fora da validação.

## Plano e regras

- Trabalhar na branch atual `main`, sem criar branch ou PR.
- Release `v0.1.7`, build monotônico `9`, após `v0.1.6` / build `8`.
- Incluir somente a correção aprovada, seus testes, documentação e metadados da release.
- Commits somente em nome de Murilo Ribeiro, sem `Co-Authored-By`.
- Preservar timer, sessões, dados e artefatos anteriores; usar `build/release-0.1.7`.
- Validar por suite sem interface, archive universal, integridade do ZIP, assinatura do app e EdDSA do Sparkle.
- Publicar ZIP no GitHub antes de publicar o appcast na `main`.

## Execução

- [x] Conferir estado remoto e versão anterior.
- [x] Atualizar versão, build e notas.
- [x] Reexecutar os 107 testes sem iniciar o aplicativo.
- [x] Gerar archive Release universal e ZIP.
- [x] Verificar versão, arquiteturas, assinatura, ZIP e feed.
- [ ] Commitar, criar tag e publicar release com asset verificado.
- [ ] Enviar `main` e confirmar feed público e release.

## Evidência local

- Suite sem interface: 107 testes / 18 suites, exit 0.
- Archive Release: `ARCHIVE SUCCEEDED`, Intel + Apple Silicon; versão 0.1.7 / build 9, mesmo bundle ID, feed, chave pública e mínimo macOS 26.5.
- ZIP: 8.059.148 bytes, SHA-256 `21bf71a04f6cb3281e5410d6a557ecf5a185a92b2355318e3cd4dc93bb802137`.
- Assinatura ad-hoc íntegra; Ed25519 validada diretamente com a chave pública embarcada no app.
- Relatório e archive preservados em `build/release-0.1.7`; nenhum aplicativo/test host iniciado.
