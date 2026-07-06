# WorkLog Electron

Versao desktop do WorkLog para Windows e Linux.

Esta implementacao nao substitui o app macOS nativo em SwiftUI. O app macOS continua em `WorkLog/`, com SwiftData, MenuBarExtra e integracoes nativas da Apple. Esta pasta contem uma segunda aplicacao, criada para distribuir o mesmo fluxo de controle de tempo em outros sistemas operacionais.

## Escopo

- Windows e Linux via Electron.
- Dados locais em SQLite.
- App local-first, sem API obrigatoria.
- Estrutura preparada para API/sincronizacao futura.
- Backup JSON para portabilidade entre versoes.
- Exportacao CSV e Excel XML.

## Regras mantidas

- Apenas uma sessao pode ficar em andamento.
- Iniciar outro projeto pausa a sessao atual automaticamente.
- Cada intervalo iniciado e pausado vira uma sessao independente.
- Sessao manual valida projeto, inicio, fim e sobreposicao de horario.
- Projetos possuem nome, cliente, valor por dia, categoria, tags, descricao, status, favorito e arquivado.
- Relatorios agrupam tempo por projeto, cliente e categoria.

## Comandos

```bash
npm install
npm run dev:renderer
npm run dev:electron
npm run test
npm run build
npm run package:linux
npm run package:win
npm run dist:linux
npm run dist:win
```

Para desenvolvimento, rode `npm run dev:renderer` em um terminal e `npm run dev:electron` em outro.

## Estrutura

```text
desktop-electron/
  electron/             processo principal, IPC, SQLite e integracoes OS
  src/shared/           contratos, formatacao e validacoes puras
  src/ui/               interface React
  src/styles/           CSS da aplicacao
  tests/                testes unitarios Vitest
```

## Dados

O banco `worklog.sqlite` fica no diretorio `userData` do Electron para cada sistema operacional. A exportacao de backup gera um JSON com:

- `exportedAt`
- `projects`
- `sessions`

Esse contrato deve ser mantido como formato comum para migracao e para uma API futura.

## CI

O workflow `.github/workflows/electron-desktop.yml` valida a aplicacao Electron e gera artefatos em runners Linux e Windows. Builds locais em macOS podem gerar pacotes `--dir` para validacao, mas os instaladores finais devem preferencialmente ser gerados no runner do proprio sistema alvo.
