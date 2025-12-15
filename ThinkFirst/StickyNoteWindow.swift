// StickyNoteWindow.swift
// Manages the floating sticky note window and contains the SwiftUI view for editing text.

import SwiftUI
import AppKit

enum DoneButtonStyle: String, CaseIterable, Identifiable {
    case automatic = "Automatic"
    case bordered = "Bordered"
    case borderedProminent = "Bordered Prominent"
    case glass = "Glass"
    case glassProminent = "Glass Prominent"

    var id: String { rawValue }
}

private struct DoneButtonStyleKey: EnvironmentKey {
    static let defaultValue: DoneButtonStyle = .glassProminent
}

extension EnvironmentValues {
    var doneButtonStyle: DoneButtonStyle {
        get { self[DoneButtonStyleKey.self] }
        set { self[DoneButtonStyleKey.self] = newValue }
    }
}

extension View {
    func doneButtonStyle(_ style: DoneButtonStyle) -> some View {
        environment(\.doneButtonStyle, style)
    }
}

private extension VerticalAlignment {
    private enum FirstLineCenter: AlignmentID {
        static func defaultValue(in dimensions: ViewDimensions) -> CGFloat {
            dimensions[VerticalAlignment.center]
        }
    }

    static let firstLineCenter = VerticalAlignment(FirstLineCenter.self)
}

private final class StickyNoteWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private struct NativeTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool

    var font: NSFont
    var textColor: NSColor
    var textContainerInset: CGSize
    var onFocusChange: ((Bool) -> Void)? = nil
    var onEndEditing: (() -> Void)? = nil

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let textView = CallbackTextView()
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.usesFindPanel = false
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.font = font
        textView.textColor = textColor
        textView.string = text
        textView.textContainerInset = NSSize(width: textContainerInset.width, height: textContainerInset.height)
        textView.textContainer?.lineFragmentPadding = 0

        textView.onFocusChange = { focused in
            DispatchQueue.main.async {
                isFocused = focused
                onFocusChange?(focused)
            }
        }
        textView.onEndEditing = {
            DispatchQueue.main.async {
                isFocused = false
                onEndEditing?()
            }
        }

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? CallbackTextView else { return }

        if textView.string != text {
            textView.string = text
        }

        if textView.font != font { textView.font = font }
        if textView.textColor != textColor { textView.textColor = textColor }

        let inset = NSSize(width: textContainerInset.width, height: textContainerInset.height)
        if textView.textContainerInset != inset { textView.textContainerInset = inset }
        textView.textContainer?.lineFragmentPadding = 0

        // Manage focus explicitly since SwiftUI FocusState doesn't apply to NSTextView.
        if isFocused {
            if nsView.window?.firstResponder !== textView {
                nsView.window?.makeFirstResponder(textView)
            }
        } else {
            if nsView.window?.firstResponder === textView {
                nsView.window?.makeFirstResponder(nil)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String

        init(text: Binding<String>) {
            _text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text = textView.string
        }
    }

    final class CallbackTextView: NSTextView {
        var onFocusChange: (Bool) -> Void = { _ in }
        var onEndEditing: () -> Void = {}
        private var windowResignObserver: Any?
        private var appResignObserver: Any?

        override func becomeFirstResponder() -> Bool {
            let became = super.becomeFirstResponder()
            if became { onFocusChange(true) }
            return became
        }

        override func resignFirstResponder() -> Bool {
            let resigned = super.resignFirstResponder()
            if resigned { onFocusChange(false) }
            return resigned
        }

        override func keyDown(with event: NSEvent) {
            // Escape ends editing.
            if event.keyCode == 53 {
                onEndEditing()
                return
            }
            super.keyDown(with: event)
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()

            if let windowResignObserver {
                NotificationCenter.default.removeObserver(windowResignObserver)
                self.windowResignObserver = nil
            }
            if let appResignObserver {
                NotificationCenter.default.removeObserver(appResignObserver)
                self.appResignObserver = nil
            }

            guard let window else { return }

            windowResignObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didResignKeyNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                self?.onEndEditing()
            }

            // Clicking into another app ends editing too.
            appResignObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didResignActiveNotification,
                object: NSApp,
                queue: .main
            ) { [weak self] _ in
                self?.onEndEditing()
            }
        }
    }
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
    @State private var isTextEditorFocused: Bool = false
    @Environment(\.doneButtonStyle) private var doneButtonStyle
    private let contentPadding: CGFloat = 16
    private let editorFont: NSFont = .systemFont(ofSize: 18)
    private var editorLineHeight: CGFloat {
        editorFont.ascender + abs(editorFont.descender) + editorFont.leading
    }

#if DEBUG
    init(previewIsEditing: Bool = false) {
        _isEditing = State(initialValue: previewIsEditing)
        _isTextEditorFocused = State(initialValue: previewIsEditing)
    }
#endif

    var body: some View {
        Group {
            if isEditing {
                NativeTextView(
                    text: $text,
                    isFocused: $isTextEditorFocused,
                    font: editorFont,
                    textColor: .white,
                    textContainerInset: CGSize(width: contentPadding, height: contentPadding),
                    onFocusChange: { focused in
                        if !focused { endEditing() }
                    },
                    onEndEditing: {
                        endEditing()
                    }
                )
                    .frame(minWidth: 250, minHeight: 160)
                    .background(Color.black.opacity(0.7))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            } else {
                Text(text)
                    .padding(contentPadding)
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
        .overlay(alignment: .topLeading) {
            if isEditing {
                HStack(alignment: .firstLineCenter) {
                    Color.clear
                        .frame(width: 1, height: editorLineHeight)
                        .accessibilityHidden(true)
                        .alignmentGuide(.firstLineCenter) { dimensions in
                            dimensions[VerticalAlignment.center]
                        }

                    Spacer()

                    doneButton
                }
                .padding(.top, contentPadding)
                .padding(.leading, contentPadding)
                .padding(.trailing, contentPadding)
            }
        }
    }

    @ViewBuilder
    private var doneButton: some View {
        switch doneButtonStyle {
        case .automatic:
            baseDoneButton.buttonStyle(.automatic)
        case .bordered:
            baseDoneButton.buttonStyle(.bordered)
        case .borderedProminent:
            baseDoneButton.buttonStyle(.borderedProminent)
        case .glass:
            baseDoneButton.buttonStyle(.glass)
        case .glassProminent:
            baseDoneButton.buttonStyle(.glassProminent)
        }
    }

    private var baseDoneButton: some View {
        Button {
            endEditing()
        } label: {
            Text("Done")
        }
        .tint(.accentColor)
        .controlSize(.small)
        .alignmentGuide(.firstLineCenter) { dimensions in
            dimensions[VerticalAlignment.center]
        }
    }

    private func endEditing() {
        isTextEditorFocused = false
        isEditing = false
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
