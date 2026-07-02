import SwiftUI
import AppKit
import Carbon.HIToolbox

struct ShortcutRecorderView: View {
    @Binding var keyCombo: KeyCombo
    @State private var isRecording = false

    var body: some View {
        Button {
            isRecording = true
        } label: {
            Text(isRecording ? "Pressione uma combinação…" : keyCombo.displayString)
                .frame(minWidth: 140)
        }
        .buttonStyle(.bordered)
        .background(
            KeyCaptureRepresentable(isRecording: $isRecording, keyCombo: $keyCombo)
                .frame(width: 0, height: 0)
        )
    }
}

private struct KeyCaptureRepresentable: NSViewRepresentable {
    @Binding var isRecording: Bool
    @Binding var keyCombo: KeyCombo

    func makeNSView(context: Context) -> KeyCaptureNSView {
        let view = KeyCaptureNSView()
        view.onCapture = { newCombo in
            keyCombo = newCombo
            isRecording = false
        }
        view.onCancel = {
            isRecording = false
        }
        return view
    }

    func updateNSView(_ nsView: KeyCaptureNSView, context: Context) {
        if isRecording {
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(nsView)
            }
        }
    }
}

private final class KeyCaptureNSView: NSView {
    var onCapture: ((KeyCombo) -> Void)?
    var onCancel: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        guard event.keyCode != kVK_Escape else {
            onCancel?()
            return
        }

        var modifiers: UInt32 = 0
        if event.modifierFlags.contains(.command) { modifiers |= UInt32(cmdKey) }
        if event.modifierFlags.contains(.option) { modifiers |= UInt32(optionKey) }
        if event.modifierFlags.contains(.control) { modifiers |= UInt32(controlKey) }
        if event.modifierFlags.contains(.shift) { modifiers |= UInt32(shiftKey) }

        onCapture?(KeyCombo(keyCode: UInt32(event.keyCode), modifiers: modifiers))
    }
}
