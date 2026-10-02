# Recuperação do hover do notch — Implementation Plan

> **For agentic workers:** executar o plano aprovado com investigação/testes independentes em paralelo e revisão final. Passos usam checkbox para registrar validação.

**Goal:** recuperar o hover quando o macOS substitui a tela ou retorna da suspensão, sem reiniciar o app.

**Architecture:** `NotchScreenResolver<Screen: AnyObject>` retém o identificador, consulta o provedor atual e seleciona telas com notch. O controlador usa essa resolução e reconcilia geometria/presentação; um observer de ciclo de vida reconcilia o manager após wake/session ativa.

**Tech Stack:** Swift, AppKit, Swift Testing, SwiftPM temporário e Xcode.

**Spec:** `docs/superpowers/specs/2026-10-01-worklog-notch-hover-recovery-design.md`

## Global Constraints

- Preservar timer, sessões, persistência, safe area, badge, histerese, foco e primeiro clique.
- Trabalhar na branch atual; não publicar nem substituir a instalação.
- Nenhuma interação com app/sessão macOS do usuário para reproduzir a falha.
- Testes com telas simuladas e centro de notificações privado; suite sem `WorkLogApp`.

## Review Focus

- Substituição da instância de tela com mesmo identificador deve continuar permitindo hover.
- Tela sem notch não pode ser selecionada; indisponibilidade temporária deve se recuperar.
- Reapresentação com painel expandido deve preservar estado e invalidar animações antigas.
- Despertar deve recuperar a apresentação sem handlers retidos após descarte.
- Falhas de resolução precisam de diagnóstico sem spam a cada 80 ms.

### Task 1: Resolver e controlador

**Files:** `WorkLog/Notch/NotchScreenResolver.swift`, `WorkLog/Notch/NotchGeometry.swift`, `WorkLog/Notch/NotchWindowController.swift`, `WorkLogTests/NotchScreenResolverTests.swift`, `WorkLog.xcodeproj/project.pbxproj`.

**Interfaces:** resolver recebe closures `screens: () -> [Screen]`, `identifier: (Screen) -> UInt32?`, `hasNotch: (Screen) -> Bool`; fornece `select(_:)`, `resolve() -> Screen?`, `reset()` e `selectedDisplayID`.

- [x] Escrever testes de substituição, liberação da instância antiga, indisponibilidade/retorno, troca de monitor e ausência de notch; verificar RED.
- [x] Implementar resolver e conectar ao controlador; preservar expansão em reapresentação e atualizar geometria recuperada.
- [x] Registrar motivo de indisponibilidade/recuperação apenas nas mudanças; verificar GREEN.

### Task 2: Recuperação de ciclo de vida

**Files:** `WorkLog/Notch/NotchLifecycleObserver.swift`, `WorkLog/Notch/DisplayModeManager.swift`, `WorkLogTests/NotchLifecycleObserverTests.swift`.

- [x] Verificar RED para wake do sistema/telas/sessão em `NotificationCenter` privado.
- [x] Implementar observer com tokens removidos ao descarte e integrar refresh do manager.
- [x] Verificar GREEN e liberação do observer, sem eventos reais do sistema.

### Task 3: Validação sem interface

**Files:** `scripts/test-headless.sh`, integração dos novos testes no projeto.

- [x] Executar suite Swift Testing em biblioteca temporária sem `WorkLogApp` e dados de produção.
- [x] Compilar app e testes com `xcodebuild build-for-testing`, sem executar app/test host.
- [x] Revisar diff, corrigir achados relevantes e registrar resultados/limitação de reprodução intermitente.

## Resultados

Revisão final apontou animação de badge fora da finalização e indisponibilidade de tela no momento do wake cancelando o polling. Correções dentro do plano aprovado:

- [x] `NotchFrameTransition` e testes determinísticos para callback antigo após invalidação e durante animação nova; usar finalização compartilhada para abertura/fechamento/badge.
- [x] `NotchScreenRecovery` e testes determinísticos para fallback sem tela seguido de disponibilidade; monitorar apenas enquanto modo preferido notch estiver em fallback.
- [x] Reexecutar suite e build-for-testing após esses ajustes.

- Resolver RED: 8 testes executados, 7 falharam por asserções com `resolve()` ainda sem implementação; compilação passou. Log: `/var/folders/4w/vcc6xq0j7f9gxc518cggzx380000gn/T/worklog-headless.cwWhO6/red.log`.
- Lifecycle RED: callbacks ausentes e subscriptions não registradas; GREEN com três testes, incluindo três notificações parametrizadas, eventos ignorados e descarte.
- `scripts/test-headless.sh`: exit 0, **98 testes / 16 suites passaram**. Log: `/tmp/worklog-hover-headless.log`. Nenhum `WorkLogApp` foi iniciado; persistência dos testes em memória/pastas temporárias.
- `xcodebuild -project WorkLog.xcodeproj -scheme WorkLog -configuration Debug -destination 'platform=macOS' -derivedDataPath /tmp/worklog-hover-recovery-derived -clonedSourcePackagesDirPath /tmp/worklog-notch-derived/SourcePackages -disableAutomaticPackageResolution build-for-testing -only-testing:WorkLogTests CODE_SIGNING_ALLOWED=NO`: exit 0, `TEST BUILD SUCCEEDED`. Log: `/tmp/worklog-hover-xcode-build.log`.
- Build mantém avisos existentes de concorrência nos serviços/viewmodels e configuração de Info.plist; nenhuma falha de compilação. `bash -n scripts/test-headless.sh`, `plutil -lint WorkLog.xcodeproj/project.pbxproj` e `git diff --check` passaram.
- Limitação: a ocorrência intermitente na sessão real não foi reproduzida, conforme restrição do usuário. Os testes comprovam a resolução/recuperação simuladas; primeiro clique/animação nativa foram preservados por revisão de código e compilação.
- Revisão independente: achado P2 da animação do badge corrigido com finalização compartilhada. `NotchFrameTransitionTests`: RED com duas falhas esperadas; GREEN 4/4. A limitação de recovery após fallback recebeu monitor dedicado: RED com quatro falhas; GREEN 5/5.
- Validação final após ajustes: `swift test --package-path /var/folders/4w/vcc6xq0j7f9gxc518cggzx380000gn/T/worklog-headless.9A0JxE --cache-path /Users/murilo/Library/Caches/WorkLog/headless-swiftpm --no-parallel --disable-xctest --enable-swift-testing` → exit 0, **107 testes / 18 suites passaram**. Log: `/tmp/worklog-hover-headless-final.log`.
- Build-for-testing final com o mesmo comando acima: exit 0, `TEST BUILD SUCCEEDED`. Log: `/tmp/worklog-hover-xcode-build-final.log`. Testes novos presentes no target Xcode; nenhum app ou test host foi executado.
