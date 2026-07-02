# Projeto: Aplicativo macOS para Controle Pessoal de Tempo de Projetos

Você é um desenvolvedor sênior especializado em macOS, SwiftUI e arquitetura de software. Sua missão é desenvolver um aplicativo completo, moderno e pronto para produção seguindo rigorosamente os requisitos abaixo.

**IMPORTANTE:** Não gere código simplificado, de demonstração ou MVP incompleto. Desenvolva uma aplicação com arquitetura profissional, escalável, organizada e preparada para evoluir.

---

# Objetivo

Desenvolver um aplicativo nativo para macOS destinado exclusivamente ao meu uso pessoal.

O objetivo é controlar o tempo gasto em projetos e demandas através de um cronômetro integrado à barra superior do macOS (Menu Bar).

O aplicativo deve possuir aparência totalmente nativa, seguindo as Human Interface Guidelines da Apple.

A experiência deve ser extremamente rápida, elegante e integrada ao sistema operacional.

---

# Tecnologias obrigatórias

Utilizar exclusivamente:

* Swift
* SwiftUI
* SwiftData
* MenuBarExtra
* Observation
* Async/Await

Arquitetura obrigatória:

* MVVM
* Repository Pattern
* Dependency Injection
* Separação completa de responsabilidades
* Código altamente organizado
* Componentes reutilizáveis
* ViewModels independentes
* Models desacoplados
* Services separados
* Helpers separados
* Extensions organizadas

Não utilizar UIKit, exceto quando realmente necessário para acessar APIs exclusivas do macOS.

---

# Compatibilidade

Compatível com versões recentes do macOS.

---

# Interface

A interface deve parecer um aplicativo criado pela própria Apple.

Referências:

* Finder
* Calendar
* Reminders
* Notes
* Music
* System Settings

Não utilizar aparência semelhante a Electron.

Toda interface deve utilizar componentes nativos do SwiftUI.

Suporte completo para:

* Light Mode
* Dark Mode

---

# Funcionamento

O aplicativo ficará residente na barra superior do macOS.

Ao clicar no ícone será exibido um Popover moderno.

O aplicativo não deverá aparecer no Dock.

O aplicativo deverá iniciar automaticamente junto com o macOS.

---

# Barra Superior

Enquanto houver um timer ativo deverá aparecer:

Número da demanda + tempo.

Exemplo:

R24901 • 01:42

Quando não existir timer ativo:

Mostrar apenas o ícone do aplicativo.

---

# Dashboard

Criar uma janela principal contendo:

Resumo do dia

Resumo da semana

Resumo do mês

Tempo total

Projetos ativos

Projetos arquivados

Últimas sessões

Projetos mais utilizados

Tempo por categoria

Tempo por cliente

Tempo por projeto

Interface moderna utilizando Sidebar.

---

# Cadastro de Projetos

Cada projeto deverá possuir:

* Nome
* Cliente
* Valor por dia
* Categoria
* Tags
* Descrição
* Status
* Arquivado

Status disponíveis:

* Ativo
* Em execução
* Impedimento
* Pronto

Categorias:

* Trabalho
* Pessoal

Permitir:

Criar

Editar

Excluir

Arquivar

Pesquisar

Filtrar

Ordenar

---

# Timer

Cada projeto possui um cronômetro.

Somente um timer pode permanecer ativo.

Caso outro timer seja iniciado:

O timer atual deverá ser pausado automaticamente.

Cada período iniciado e pausado deverá gerar uma sessão independente.

Exemplo:

08:00 - 09:15

10:30 - 12:00

14:10 - 18:00

Permitir:

Iniciar

Pausar

Continuar

Encerrar

Adicionar sessão manualmente

Editar sessões

Excluir sessões

---

# Pausas automáticas

O timer deverá ser pausado automaticamente quando ocorrer:

Computador suspenso

Tela bloqueada

Sistema entrar em repouso

Computador permanecer inativo pelo tempo configurado nas preferências

Quando retornar deverá continuar pausado até o usuário iniciar novamente.

---

# Popover

Ao clicar no Menu Bar deverá abrir um Popover contendo:

Projeto atual

Tempo atual

Botão iniciar

Botão pausar

Projetos recentes

Projetos favoritos

Tempo total do dia

Atalho para Dashboard

Configurações

Sair

Tudo com aparência semelhante aos menus nativos do macOS.

---

# Sessões

Cada sessão deverá armazenar:

Projeto

Data

Hora inicial

Hora final

Duração

Observação

Categoria

Status

Permitir edição completa posteriormente.

---

# Relatórios

Criar relatórios:

Hoje

Ontem

Semana

Mês

Ano

Período personalizado

Todos deverão possuir filtros por:

Projeto

Cliente

Categoria

Status

Tags

---

# Exportação

Permitir exportar relatórios para:

CSV

Excel

PDF

---

# Pesquisa

Criar pesquisa rápida por:

Projeto

Cliente

Descrição

Tags

Status

Categoria

---

# Configurações

Criar uma tela completa contendo:

Inicializar junto com macOS

Tempo para pausa automática por inatividade

Mostrar segundos

Tema

Formato de hora

Atalhos globais

Gerenciamento de backup

Importação

Exportação

---

# Atalhos Globais

Criar sistema completo para configuração de atalhos.

O usuário poderá definir qualquer combinação de teclas.

Exemplos:

Iniciar timer

Pausar timer

Abrir Dashboard

Abrir Popover

Pesquisar projeto

Novo projeto

Todos os atalhos deverão ser configuráveis.

---

# Persistência

Utilizar SwiftData.

Nunca utilizar dados temporários.

Toda alteração deverá ser persistida imediatamente.

---

# Estrutura do Projeto

Organizar o projeto em módulos.

Exemplo:

App

Core

Models

Repositories

Services

Persistence

ViewModels

Views

Components

Utilities

Extensions

Resources

Settings

Reports

Dashboard

MenuBar

Projects

Timer

Export

Tests

Cada responsabilidade deve permanecer isolada.

---

# Regras de Negócio

Somente um timer ativo.

Ao iniciar outro timer:

Pausar automaticamente o anterior.

Não permitir timers duplicados.

Não permitir sessões inválidas.

Não permitir datas inconsistentes.

Validar todos os formulários.

Evitar duplicidade de projetos.

---

# Performance

Aplicação deve permanecer extremamente rápida.

Suportar milhares de projetos e centenas de milhares de sessões.

Utilizar consultas eficientes.

Evitar processamento desnecessário.

---

# Qualidade

Todo código deverá possuir:

Arquitetura limpa

SOLID

Clean Code

Boas práticas Swift

Comentários apenas quando realmente necessários

Nomes claros

Baixo acoplamento

Alta coesão

---

# Testes

Criar:

Testes Unitários

Testes de Interface

Testes das regras de negócio

Testes dos Repositories

Testes dos Services

---

# Documentação

Gerar documentação do projeto contendo:

Arquitetura

Estrutura de pastas

Fluxo do aplicativo

Fluxo do Timer

Fluxo do Menu Bar

Fluxo de Persistência

Decisões arquiteturais

Como executar

Como compilar

Como gerar Release

---

# Resultado esperado

O resultado final deve ser um aplicativo profissional, nativo do macOS, com aparência equivalente aos aplicativos da Apple, arquitetura escalável, código pronto para produção, organizado e facilmente expansível.

Não simplifique nenhuma funcionalidade.

Sempre priorize qualidade de código, experiência do usuário, desempenho, organização e manutenibilidade.

Implemente o projeto completo, gerando todos os arquivos necessários, sem omitir partes importantes da arquitetura.

