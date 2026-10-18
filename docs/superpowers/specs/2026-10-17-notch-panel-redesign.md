# Painel do notch — visual aprovado

Escopo autorizado: somente o painel do notch do WorkLog. Referência aprovada pelo usuário: imagem `exec-139b1f05-88d4-4779-843a-d4cc05ef4e14.png`, gerada nesta conversa. O usuário aprovou a implementação após corrigir as curvas superiores.

Painel preto/grafite, integrado à câmera e à borda física da tela por ombros côncavos nas duas laterais superiores. Corpo de 340 pontos; ombros de 14 pontos para cada lado; cantos inferiores de 20 pontos. Conteúdo abaixo da área segura da câmera. Altura intrínseca e lista com rolagem limitada, mantendo controles e rodapé visíveis.

Conteúdo: marca discreta e fixação; projeto/cliente; cronômetro grande; Pausar/Encerrar; busca por nome/cliente; favoritos e recentes sem duplicação; total fechado do dia; Dashboard, Configurações e menu Sair. Estados: em execução, pausado com Retomar, e vazio com orientação para escolher projeto. A busca inclui projetos não arquivados além dos recentes. A cor é identificação visual determinística, sem alterar o modelo de projetos.

Regras: um timer ativo; trocar projeto pausa o anterior; retomar usa TimerService.resume e cria novo intervalo; nenhuma mudança no domínio, armazenamento ou sincronização. Fixação é transitória e impede o recolhimento ao retirar o cursor. Preservar badge colapsado, fallback para barra de menu, foco no clique, histerese e correções locais existentes. Popover da barra de menu mantém sua aparência.

Validar com testes sem iniciar WorkLog.app, compilação Xcode e capturas SwiftUI fora da tela usando dados sintéticos. Não publicar, instalar, alterar Spaces, movimentar o cursor ou testar suspensão do Mac. Trabalhar na branch atual, sem commit/PR automático.
