# Recuperação do hover do notch

Plano aprovado pelo usuário: corrigir a perda de hover que deixa o painel recolhido até reiniciar o WorkLog. Os logs mostram cliques no painel recolhido sem transição; a referência `weak` a `NSScreen` e o retorno silencioso do polling são a hipótese principal, ainda sem comprovação no instante da ocorrência.

Guardar somente o identificador do monitor e resolver sua instância nas telas atuais em cada avaliação. Preferir o monitor selecionado enquanto ele tiver notch, selecionar outro monitor com notch quando necessário e tolerar ausência temporária de telas. Registrar interrupção e recuperação sem emitir logs a cada ciclo.

Reconciliar a apresentação após despertar do sistema, das telas e retorno da sessão. A reapresentação preserva a expansão existente e invalida conclusões de animações anteriores. O hover conserva suas zonas e histerese; foco e primeiro clique seguem o comportamento atual.

A revisão detectou que a animação de largura do badge também precisa da mesma finalização que abertura/fechamento: callbacks atrasados reaplicam somente a geometria atual, sem interromper uma animação mais nova. Se o modo preferido for notch e nenhuma tela estiver disponível durante o despertar, monitorar a disponibilidade a cada segundo enquanto a barra de menu fornece o fallback. Parar o monitor antes de recuperar a apresentação ou quando o usuário selecionar barra de menu; não consultar persistência nem reapresentar continuamente enquanto não houver tela.

Preservar timer, sessões, persistência, safe area, badge e fallback à barra de menu. Trabalhar na branch atual. Não publicar nem substituir a instalação.

Restrição expressa do usuário: não tentar reproduzir o problema intermitente em sua sessão do Mac. Validar com provedores de telas simulados, centro de notificações privado, suite sem lançamento do app e compilação. Não mover mouse, trocar telas, suspender o Mac nem iniciar o WorkLog para testes.
