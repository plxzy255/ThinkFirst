// StickyNoteWindow.swift
// Manages the floating sticky note window and contains the SwiftUI view for editing text.

import SwiftUI
import AppKit

// The content that appears in the sticky note window
struct StickyNoteView: View {
    @AppStorage("stickyNoteText") private var text: String = ""
    var body: some View {
        TextEditor(text: $text)
            .padding()
            .frame(minWidth: 250, minHeight: 160)
            .background(Color.yellow.opacity(0.7))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .font(.system(size: 18))
            .scrollContentBackground(.hidden)
    }
}

// Controls the sticky note window itself
class StickyNoteWindowController: NSWindowController {
    init() {
        let hosting = NSHostingController(rootView: StickyNoteView())
        let window = NSWindow(contentViewController: hosting)
        window.title = "Sticky Note"
        window.setContentSize(NSSize(width: 260, height: 180))
        window.isReleasedWhenClosed = false
        window.styleMask = [.titled, .closable, .resizable, .fullSizeContentView]
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
