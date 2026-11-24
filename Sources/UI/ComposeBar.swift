import SwiftUI

/// Floating text field at the bottom of the phone screen. Text is edited locally on the Mac
/// (instant, with Polish characters and corrections) and sent to the iPhone in one go.
struct ComposeBar: View {
    @EnvironmentObject private var model: MirrorModel
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "keyboard").foregroundStyle(.secondary)
            TextField("Type for iPhone…", text: $model.composeText)
                .textFieldStyle(.plain)
                .focused($focused)
                .onSubmit { model.sendComposed() }
                .onExitCommand { model.cancelComposing() }
            Button { model.sendComposed() } label: {
                Image(systemName: "arrow.up.circle.fill").font(.system(size: 20))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
            .help("Send to iPhone (Return) · Esc cancels")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.25), radius: 8, y: 2)
        .padding(10)
        .onAppear {
            focused = true
            // A focused NSTextField selects all its text; put the caret at the end instead,
            // otherwise the next keystroke would replace the first typed character.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { Self.moveCaretToEnd() }
        }
    }

    private static func moveCaretToEnd() {
        for window in NSApp.windows {
            guard let editor = window.firstResponder as? NSTextView, editor.isFieldEditor else { continue }
            editor.setSelectedRange(NSRange(location: (editor.string as NSString).length, length: 0))
        }
    }
}
