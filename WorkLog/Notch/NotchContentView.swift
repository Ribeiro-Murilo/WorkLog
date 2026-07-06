import SwiftUI

struct NotchContentView<ExpandedContent: View, CollapsedTrailing: View>: View {
    let isExpanded: Bool
    /// Largura do recorte físico do notch. No estado colapsado, a área da esquerda
    /// (preta, que se funde com o hardware) ocupa exatamente essa largura, e o que
    /// sobra à direita é usado pelo `collapsedTrailing` (ex.: o timer).
    let notchWidth: CGFloat
    /// Altura do recorte físico do notch. O painel expandido é ancorado no topo físico
    /// da tela, então o conteúdo expandido recebe esse tanto de padding no topo para não
    /// ficar desenhado atrás da câmera (invisível) nem cortado pela borda da tela.
    let notchHeight: CGFloat
    @ViewBuilder var expandedContent: () -> ExpandedContent
    @ViewBuilder var collapsedTrailing: () -> CollapsedTrailing

    init(
        isExpanded: Bool,
        notchWidth: CGFloat,
        notchHeight: CGFloat,
        @ViewBuilder expandedContent: @escaping () -> ExpandedContent = { EmptyView() },
        @ViewBuilder collapsedTrailing: @escaping () -> CollapsedTrailing = { EmptyView() }
    ) {
        self.isExpanded = isExpanded
        self.notchWidth = notchWidth
        self.notchHeight = notchHeight
        self.expandedContent = expandedContent
        self.collapsedTrailing = collapsedTrailing
    }

    var body: some View {
        Group {
            if isExpanded {
                expandedBody
            } else {
                collapsedBody
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.25), value: isExpanded)
    }

    private var expandedBody: some View {
        ZStack {
            // Base sólida escura garante que o painel SEMPRE tenha fundo,
            // mesmo quando o material translúcido não renderiza nada atrás
            // do notch (topo da tela, sem pixels reais por trás da janela).
            ZStack {
                Rectangle().fill(Color.black)
                NotchVisualEffectView(material: .menu)
                Rectangle().fill(.ultraThinMaterial.opacity(0.5))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(NotchShape(cornerRadius: 20))
            .overlay(
                NotchShape(cornerRadius: 20)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )

            expandedContent()
                .padding(.top, notchHeight)
        }
    }

    private var collapsedBody: some View {
        HStack(spacing: 0) {
            // Região alinhada ao recorte físico do notch: preto chapado (se funde
            // com o hardware) + o pontinho indicador.
            ZStack {
                NotchShape().fill(Color.black)
                Circle()
                    .fill(.white.opacity(0.6))
                    .frame(width: 4, height: 4)
            }
            .frame(width: notchWidth)

            // Região à direita do notch: transparente (não cobre a barra de menus)
            // e mostra o conteúdo colapsado, como o timer em execução.
            collapsedTrailing()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
