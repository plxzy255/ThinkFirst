// StickyNoteWindow.swift
// Manages the floating sticky note window and contains the SwiftUI view for editing text.

import SwiftUI
import AppKit

// The content that appears in the sticky note window
struct StickyNoteView: View {
    @AppStorage("stickyNoteText") private var text: String = ""
    @State private var isEditing: Bool = false
    @FocusState private var isTextEditorFocused: Bool

    var onDrag: (DragGesture.Value) -> Void

    var body: some View {
        Group {
            if isEditing {
                TextEditor(text: $text)
                    .focused($isTextEditorFocused)
                    .onChange(of: isTextEditorFocused, perform: { focused in
                        if !focused {
                            isEditing = false
                        }
                    })
                    .padding()
                    .frame(minWidth: 250, minHeight: 160)
                    .background(Color.black.opacity(0.7))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .font(.system(size: 18))
                    .scrollContentBackground(.hidden)
            } else {
                Text(text)
                    .padding()
                    .frame(minWidth: 250, minHeight: 160, alignment: .topLeading)
                    .background(Color.black.opacity(0.7))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .font(.system(size: 18))
                    .onTapGesture(count: 2) {
                        isEditing = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            isTextEditorFocused = true
                        }
                    }
            }
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture()
                .onChanged { value in
                    onDrag(value)
                }
        )
    }
}

// Controls the sticky note window itself
class StickyNoteWindowController: NSWindowController {
    private var lastDragTranslation = CGSize.zero
    init() {
        let hosting = NSHostingController(rootView: StickyNoteView { _ in })
        let window = NSWindow(contentViewController: hosting)
        window.title = "Sticky Note"
        window.setContentSize(NSSize(width: 260, height: 180))
        window.isReleasedWhenClosed = false
        // Removes title bar and window controls for a cleaner sticky note appearance
        window.styleMask = [.borderless, .resizable, .fullSizeContentView]
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenNone]
        window.isOpaque = false
        window.backgroundColor = .clear
        super.init(window: window)
        // Reset drag translation on drag end
        hosting.rootView.onDrag = { [weak self] dragValue in
            guard let self = self, let window = self.window else { return }
            var frame = window.frame
            frame.origin.x += dragValue.translation.width - self.lastDragTranslation.width
            frame.origin.y -= dragValue.translation.height - self.lastDragTranslation.height
            window.setFrame(frame, display: true)
            self.lastDragTranslation = dragValue.translation
        }
    }
    required init?(coder: NSCoder) { super.init(coder: coder) }

    func showStickyNote() {
        self.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

