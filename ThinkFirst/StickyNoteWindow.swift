// StickyNoteWindow.swift
// Manages the floating sticky note window and contains the SwiftUI view for editing text.

import SwiftUI
import AppKit

private final class StickyNoteWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private struct WindowDragOverlay: NSViewRepresentable {
    var enabled: Bool
    var onDoubleClick: () -> Void

    func makeNSView(context: Context) -> DragOverlayView {
        let view = DragOverlayView()
        view.enabled = enabled
        view.onDoubleClick = onDoubleClick
        return view
    }

    func updateNSView(_ nsView: DragOverlayView, context: Context) {
        nsView.enabled = enabled
        nsView.onDoubleClick = onDoubleClick
    }

    final class DragOverlayView: NSView {
        var enabled: Bool = false
        var onDoubleClick: () -> Void = {}

        override func hitTest(_ point: NSPoint) -> NSView? {
            enabled ? self : nil
        }

        override func mouseDown(with event: NSEvent) {
            guard enabled else {
                super.mouseDown(with: event)
                return
            }

            if event.clickCount >= 2 {
                onDoubleClick()
                return
            }

            window?.performDrag(with: event)
        }
    }
}

// The content that appears in the sticky note window
struct StickyNoteView: View {
    @AppStorage("stickyNoteText") private var text: String = ""
    @State private var isEditing: Bool = false
    @FocusState private var isTextEditorFocused: Bool

    var body: some View {
        Group {
            if isEditing {
                TextEditor(text: $text)
                    .focused($isTextEditorFocused)
                    .onChange(of: isTextEditorFocused) { _, focused in
                        if !focused { isEditing = false }
                    }
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
            }
        }
        .overlay {
            WindowDragOverlay(enabled: !isEditing) {
                isEditing = true
                DispatchQueue.main.async {
                    isTextEditorFocused = true
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            if isEditing {
                Button {
                    // End editing and dismiss focus
                    isTextEditorFocused = false
                    isEditing = false
                } label: {
                    Text("Done")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .padding(8)
            }
        }
    }
}

// Controls the sticky note window itself
class StickyNoteWindowController: NSWindowController {
    init() {
        let hosting = NSHostingController(rootView: StickyNoteView())
        let window = StickyNoteWindow(contentViewController: hosting)
        window.title = "Sticky Note"
        window.setContentSize(NSSize(width: 260, height: 180))
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        // Removes title bar and window controls for a cleaner sticky note appearance
        window.styleMask = [.borderless, .resizable, .fullSizeContentView]
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenNone]
        window.isOpaque = false
        window.backgroundColor = .clear
        super.init(window: window)
    }
    required init?(coder: NSCoder) { super.init(coder: coder) }

    func showStickyNote() {
        self.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

