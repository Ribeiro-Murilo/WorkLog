import Foundation
import SwiftData
@testable import WorkLog

@MainActor
private let sharedTestContainer: ModelContainer = {
    let schema = Schema([Project.self, Session.self, AppSettings.self, ShortcutBinding.self, Invoice.self])
    let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    return try! ModelContainer(for: schema, configurations: [configuration])
}()

/// Criar um `ModelContainer` novo por teste trava o SwiftData nesta toolchain quando repetido
/// muitas vezes no mesmo processo. Por isso reutilizamos um único container e limpamos os
/// dados entre os testes para garantir isolamento.
@MainActor
func makeInMemoryContext() -> ModelContext {
    let context = ModelContext(sharedTestContainer)
    try? context.delete(model: Session.self)
    try? context.delete(model: Project.self)
    try? context.delete(model: AppSettings.self)
    try? context.delete(model: ShortcutBinding.self)
    try? context.delete(model: Invoice.self)
    try? context.save()
    return context
}
