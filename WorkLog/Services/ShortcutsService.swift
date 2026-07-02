import Foundation
import Carbon.HIToolbox

protocol ShortcutsServiceProtocol: AnyObject {
    func registerDefaultsIfNeeded() throws
    func register(action: ShortcutAction, handler: @escaping () -> Void) throws
    func updateBinding(action: ShortcutAction, keyCombo: KeyCombo) throws
    func unregisterAll()
}

final class ShortcutsService: ShortcutsServiceProtocol {
    private let repository: ShortcutBindingRepositoryProtocol
    private let hotKeyManager = CarbonHotKeyManager()
    private var registeredHotKeyIDs: [ShortcutAction: UInt32] = [:]
    private var handlers: [ShortcutAction: () -> Void] = [:]

    @MainActor
    init(repository: ShortcutBindingRepositoryProtocol) {
        self.repository = repository
    }

    @MainActor
    static let defaultBindings: [ShortcutAction: KeyCombo] = [
        .startTimer: KeyCombo(keyCode: UInt32(kVK_ANSI_S), modifiers: UInt32(cmdKey | shiftKey)),
        .pauseTimer: KeyCombo(keyCode: UInt32(kVK_ANSI_P), modifiers: UInt32(cmdKey | shiftKey)),
        .openDashboard: KeyCombo(keyCode: UInt32(kVK_ANSI_D), modifiers: UInt32(cmdKey | shiftKey)),
        .openPopover: KeyCombo(keyCode: UInt32(kVK_ANSI_W), modifiers: UInt32(cmdKey | shiftKey)),
        .searchProject: KeyCombo(keyCode: UInt32(kVK_ANSI_F), modifiers: UInt32(cmdKey | shiftKey)),
        .newProject: KeyCombo(keyCode: UInt32(kVK_ANSI_N), modifiers: UInt32(cmdKey | shiftKey)),
    ]

    @MainActor
    func registerDefaultsIfNeeded() throws {
        for action in ShortcutAction.allCases {
            if try repository.fetch(for: action) == nil, let combo = Self.defaultBindings[action] {
                _ = try repository.upsert(action: action, keyCombo: combo, isEnabled: true)
            }
        }
    }

    @MainActor
    func register(action: ShortcutAction, handler: @escaping () -> Void) throws {
        handlers[action] = handler
        guard let binding = try repository.fetch(for: action), binding.isEnabled else { return }
        installHotKey(action: action, keyCombo: binding.keyCombo)
    }

    @MainActor
    func updateBinding(action: ShortcutAction, keyCombo: KeyCombo) throws {
        _ = try repository.upsert(action: action, keyCombo: keyCombo, isEnabled: true)
        installHotKey(action: action, keyCombo: keyCombo)
    }

    func unregisterAll() {
        registeredHotKeyIDs.values.forEach { hotKeyManager.unregister(id: $0) }
        registeredHotKeyIDs.removeAll()
    }

    private func installHotKey(action: ShortcutAction, keyCombo: KeyCombo) {
        if let existingID = registeredHotKeyIDs[action] {
            hotKeyManager.unregister(id: existingID)
        }
        let id = hotKeyManager.register(keyCode: keyCombo.keyCode, modifiers: keyCombo.modifiers) { [weak self] in
            self?.handlers[action]?()
        }
        registeredHotKeyIDs[action] = id
    }
}

/// Wrapper de baixo nível sobre a Carbon Event Manager API para registrar atalhos globais.
/// Necessário pois o AppKit não expõe uma API pública para hotkeys globais sem exigir
/// permissão de Acessibilidade (como monitores globais de `NSEvent`).
final class CarbonHotKeyManager {
    private var hotKeyRefs: [UInt32: EventHotKeyRef] = [:]
    private var callbacks: [UInt32: () -> Void] = [:]
    private var eventHandlerRef: EventHandlerRef?
    private var nextID: UInt32 = 1

    private static let signature: FourCharCode = {
        var result: FourCharCode = 0
        for scalar in "WLOG".unicodeScalars { result = (result << 8) + FourCharCode(scalar.value) }
        return result
    }()

    @discardableResult
    func register(keyCode: UInt32, modifiers: UInt32, callback: @escaping () -> Void) -> UInt32 {
        let id = nextID
        nextID += 1

        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        var hotKeyRef: EventHotKeyRef?
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetEventDispatcherTarget(), 0, &hotKeyRef)

        if status == noErr, let hotKeyRef {
            hotKeyRefs[id] = hotKeyRef
            callbacks[id] = callback
        }

        installHandlerIfNeeded()
        return id
    }

    func unregister(id: UInt32) {
        if let ref = hotKeyRefs[id] {
            UnregisterEventHotKey(ref)
            hotKeyRefs.removeValue(forKey: id)
        }
        callbacks.removeValue(forKey: id)
    }

    private func installHandlerIfNeeded() {
        guard eventHandlerRef == nil else { return }

        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyPressed))
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()

        InstallEventHandler(GetEventDispatcherTarget(), { _, eventRef, userData in
            guard let eventRef, let userData else { return OSStatus(eventNotHandledErr) }

            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                eventRef,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            guard status == noErr else { return status }

            let manager = Unmanaged<CarbonHotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            manager.callbacks[hotKeyID.id]?()
            return noErr
        }, 1, &eventSpec, selfPointer, &eventHandlerRef)
    }
}
