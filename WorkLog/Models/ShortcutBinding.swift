import Foundation
import SwiftData

@Model
final class ShortcutBinding {
    var actionRawValue: String = ShortcutAction.startTimer.rawValue
    var keyCode: UInt32 = 0
    var modifiers: UInt32 = 0
    var isEnabled: Bool = true
    var updatedAt: Date = Date.now

    var action: ShortcutAction {
        get { ShortcutAction(rawValue: actionRawValue) ?? .startTimer }
        set { actionRawValue = newValue.rawValue }
    }

    var keyCombo: KeyCombo {
        get { KeyCombo(keyCode: keyCode, modifiers: modifiers) }
        set {
            keyCode = newValue.keyCode
            modifiers = newValue.modifiers
        }
    }

    init(action: ShortcutAction, keyCombo: KeyCombo, isEnabled: Bool = true) {
        self.actionRawValue = action.rawValue
        self.keyCode = keyCombo.keyCode
        self.modifiers = keyCombo.modifiers
        self.isEnabled = isEnabled
        self.updatedAt = .now
    }
}
