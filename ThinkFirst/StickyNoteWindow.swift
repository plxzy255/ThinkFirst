// StickyNoteWindow.swift
// Manages the floating sticky note window and contains the SwiftUI view for editing text.

import SwiftUI
import AppKit
import CoreLocation

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

    var isEditable: Bool
    var font: NSFont
    var textColor: NSColor
    var textContainerInset: CGSize
    var onFocusChange: ((Bool) -> Void)? = nil
    var onEndEditing: (() -> Void)? = nil
    var onMeasuredContentHeight: ((NSWindow, CGFloat) -> Void)? = nil

    private final class MeasuringScrollView: NSScrollView {
        var onLayout: (() -> Void)?
        override func layout() {
            super.layout()
            onLayout?()
        }
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = MeasuringScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.verticalScrollElasticity = .none


        let textView = CallbackTextView()
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.isEditable = isEditable
        textView.isSelectable = isEditable
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
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false

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

        scrollView.onLayout = { [weak scrollView, weak textView] in
            guard
                let scrollView,
                let textView,
                let window = scrollView.window,
                let onMeasuredContentHeight
            else { return }

            let measured = Self.measuredContentHeight(for: textView)
            DispatchQueue.main.async {
                onMeasuredContentHeight(window, measured)
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

        if textView.isEditable != isEditable {
            textView.isEditable = isEditable
        }
        if textView.isSelectable != isEditable {
            textView.isSelectable = isEditable
        }

        if textView.font != font { textView.font = font }
        if textView.textColor != textColor { textView.textColor = textColor }

        let inset = NSSize(width: textContainerInset.width, height: textContainerInset.height)
        if textView.textContainerInset != inset { textView.textContainerInset = inset }
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false

        // Ensure the document view is at least as tall as the visible region; otherwise you'll see
        // "dead space" at the bottom where clicks won't place the caret.
        let contentSize = nsView.contentSize
        let requiredHeight = Self.measuredContentHeight(for: textView)
        var newFrame = textView.frame
        newFrame.size.width = contentSize.width
        newFrame.size.height = max(newFrame.size.height, contentSize.height, requiredHeight)
        if textView.frame != newFrame {
            textView.frame = newFrame
        }

        if let window = nsView.window, let onMeasuredContentHeight {
            DispatchQueue.main.async {
                onMeasuredContentHeight(window, requiredHeight)
            }
        }

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
        Coordinator(text: $text, onMeasuredContentHeight: onMeasuredContentHeight)
    }

    private static func measuredContentHeight(for textView: NSTextView) -> CGFloat {
        guard
            let textContainer = textView.textContainer,
            let layoutManager = textView.layoutManager
        else {
            return max(0, textView.bounds.height)
        }

        layoutManager.ensureLayout(for: textContainer)
        let usedHeight = layoutManager.usedRect(for: textContainer).height
        let font = textView.font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let lineHeight = layoutManager.defaultLineHeight(for: font)

        return ceil(max(usedHeight, lineHeight) + textView.textContainerInset.height * 2)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        private let onMeasuredContentHeight: ((NSWindow, CGFloat) -> Void)?

        init(text: Binding<String>, onMeasuredContentHeight: ((NSWindow, CGFloat) -> Void)?) {
            _text = text
            self.onMeasuredContentHeight = onMeasuredContentHeight
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text = textView.string

            guard
                let window = textView.window,
                let onMeasuredContentHeight
            else { return }

            onMeasuredContentHeight(window, NativeTextView.measuredContentHeight(for: textView))
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

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
            // Allow dragging the window even when it isn't key/focused.
            enabled
        }

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
    static let contentPadding: CGFloat = 16
    static let fontSize: CGFloat = 18
    private static let minLines: CGFloat = 2

	@AppStorage("stickyNoteText") private var text: String = ""
	@AppStorage("stickyNoteInactiveBackgroundOpacity") private var inactiveBackgroundOpacity: Double = 0.14
	@AppStorage("prayerEnabled") private var prayerEnabled: Bool = false
	@State private var isEditing: Bool = false
	@State private var isTextEditorFocused: Bool = false
	@State private var prayerAccessoryHeight: CGFloat = 0
	@Environment(\.doneButtonStyle) private var doneButtonStyle
	@Environment(\.controlActiveState) private var controlActiveState
	@ObservedObject private var prayerLocationManager = PrayerLocationManager.shared
	private let editorFont: NSFont = .systemFont(ofSize: StickyNoteView.fontSize)
    private var editorLineHeight: CGFloat {
        editorFont.ascender + abs(editorFont.descender) + editorFont.leading
    }
    private var baseMinContentHeight: CGFloat {
        let lineHeight = ceil(editorLineHeight)
        return ceil(StickyNoteView.contentPadding * 2 + lineHeight * StickyNoteView.minLines)
    }

	private var isWindowActive: Bool { controlActiveState == .key }
	private var combinedBaseMinContentHeight: CGFloat {
		baseMinContentHeight + (prayerEnabled ? prayerAccessoryHeight : 0)
	}

#if DEBUG
    init(previewIsEditing: Bool = false) {
        _isEditing = State(initialValue: previewIsEditing)
        _isTextEditorFocused = State(initialValue: previewIsEditing)
    }
#endif

	var body: some View {
		VStack(spacing: 0) {
			NativeTextView(
				text: $text,
				isFocused: $isTextEditorFocused,
				isEditable: isEditing,
				font: editorFont,
				textColor: .white,
				textContainerInset: CGSize(width: StickyNoteView.contentPadding, height: StickyNoteView.contentPadding),
				onFocusChange: { focused in
					if !focused { endEditing() }
				},
				onEndEditing: {
					endEditing()
				},
				onMeasuredContentHeight: { window, measuredContentHeight in
					let accessory = prayerEnabled ? prayerAccessoryHeight : 0
					let desired = measuredContentHeight + accessory
					updateWindowHeightConstraints(window, desiredContentHeight: desired)
					growWindowIfNeeded(window, desiredContentHeight: desired)
				}
			)
			.layoutPriority(1)

			if prayerEnabled {
				prayerAccessoryView
					.background {
						GeometryReader { proxy in
							Color.clear
								.preference(key: PrayerAccessoryHeightPreferenceKey.self, value: proxy.size.height)
						}
					}
			}
		}
		.onPreferenceChange(PrayerAccessoryHeightPreferenceKey.self) { prayerAccessoryHeight = $0 }
		.onAppear {
			if prayerEnabled {
				prayerLocationManager.requestAccessAndLocation()
			}
		}
		.onChange(of: prayerEnabled) { _, enabled in
			if enabled {
				prayerLocationManager.requestAccessAndLocation()
			}
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity)
		.background {
			if isWindowActive {
				if #available(macOS 26.0, *) {
					Color.clear
						.glassEffect(.regular, in: .rect(cornerRadius: 16))
				} else {
					Rectangle().fill(.ultraThinMaterial)
				}
			} else {
				Color.black.opacity(inactiveBackgroundOpacity)
			}
		}
		.clipShape(RoundedRectangle(cornerRadius: 16))
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
				.padding(.top, StickyNoteView.contentPadding)
				.padding(.leading, StickyNoteView.contentPadding)
				.padding(.trailing, StickyNoteView.contentPadding)
			}
		}
	}

	@ViewBuilder
	private var prayerAccessoryView: some View {
		VStack(spacing: 0) {
			Divider().opacity(0.25)
			if let coordinate = prayerLocationManager.lastKnownCoordinate {
				PrayerSectionView(coordinate: coordinate)
			} else {
				Text(prayerLocationPlaceholderText)
					.font(.system(size: 13))
					.foregroundStyle(.secondary)
					.padding(.vertical, 10)
					.padding(.horizontal, StickyNoteView.contentPadding)
			}
		}
	}

	private var prayerLocationPlaceholderText: String {
		switch prayerLocationManager.authorizationStatus {
		case .authorized, .authorizedAlways:
			return "Getting location…"
		case .notDetermined:
			return "Allow location access in Settings to show prayer times."
		case .restricted, .denied:
			return "Location access is off. Enable it in System Settings to show prayer times."
		@unknown default:
			return "Location status unknown."
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

	private func updateWindowHeightConstraints(_ window: NSWindow, desiredContentHeight: CGFloat) {
		let maxHeight = window.contentMaxSize.height > 0 ? window.contentMaxSize.height : desiredContentHeight
		let clampedHeight = min(max(desiredContentHeight, combinedBaseMinContentHeight), maxHeight)

        // Keep the window from being resized smaller than the content height (so you don't end up scrolling
        // immediately after manually shrinking the window).
        if window.contentMinSize.height != clampedHeight {
            window.contentMinSize.height = clampedHeight
        }
    }

	private func growWindowIfNeeded(_ window: NSWindow, desiredContentHeight: CGFloat) {
		guard !window.inLiveResize else { return }

		let minHeight = max(window.contentMinSize.height, combinedBaseMinContentHeight)
		let maxHeight = window.contentMaxSize.height > 0 ? window.contentMaxSize.height : desiredContentHeight
		let clampedHeight = min(max(desiredContentHeight, minHeight), maxHeight)

        let currentContentHeight = window.contentRect(forFrameRect: window.frame).height
        guard clampedHeight > currentContentHeight + 1 else { return }

        let currentContentWidth = window.contentRect(forFrameRect: window.frame).width
        let targetContentRect = NSRect(origin: .zero, size: NSSize(width: currentContentWidth, height: clampedHeight))
        let targetFrameHeight = window.frameRect(forContentRect: targetContentRect).height

        var newFrame = window.frame
        let delta = targetFrameHeight - newFrame.size.height
        newFrame.origin.y -= delta
        newFrame.size.height = targetFrameHeight
        window.setFrame(newFrame, display: true, animate: true)
	}
}

private struct PrayerAccessoryHeightPreferenceKey: PreferenceKey {
	static var defaultValue: CGFloat = 0
	static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

// Controls the sticky note window itself
class StickyNoteWindowController: NSWindowController, NSWindowDelegate {
    private static let minWidth: CGFloat = 260
    private static let maxWidth: CGFloat = 520
    private static let minLines: CGFloat = 2
    private static let maxLines: CGFloat = 24

    private static var lineHeight: CGFloat {
        let font = NSFont.systemFont(ofSize: StickyNoteView.fontSize)
        return ceil(font.ascender + abs(font.descender) + font.leading)
    }

    private static func contentHeight(lines: CGFloat) -> CGFloat {
        ceil(StickyNoteView.contentPadding * 2 + lineHeight * lines)
    }

    private static let minContentSize: NSSize = {
        NSSize(width: minWidth, height: contentHeight(lines: minLines))
    }()

	private static let maxAccessoryHeight: CGFloat = 80
	private static let maxContentSize: NSSize = {
		NSSize(width: maxWidth, height: contentHeight(lines: maxLines) + maxAccessoryHeight)
	}()

    init() {
        let hosting = NSHostingController(rootView: StickyNoteView())
        // Prevent SwiftUI's content from driving the window size when the view hierarchy changes
        // (e.g. toggling between read/edit modes).
        hosting.sizingOptions = []
        let window = StickyNoteWindow(contentViewController: hosting)
        window.title = "Sticky Note"
        window.setContentSize(Self.minContentSize)
        window.contentMinSize = Self.minContentSize
        window.contentMaxSize = Self.maxContentSize
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        // Removes title bar and window controls for a cleaner sticky note appearance
        window.styleMask = [.borderless, .resizable, .fullSizeContentView]
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenNone]
        window.isOpaque = false
        window.backgroundColor = .clear
        super.init(window: window)
        window.delegate = self
    }
    required init?(coder: NSCoder) { super.init(coder: coder) }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        // Width limits are fixed; height minimum is dynamic (tracks text content).
        let minContent = NSSize(width: Self.minContentSize.width, height: sender.contentMinSize.height)
        let maxContent = NSSize(width: Self.maxContentSize.width, height: sender.contentMaxSize.height)
        let minFrame = sender.frameRect(forContentRect: NSRect(origin: .zero, size: minContent)).size
        let maxFrame = sender.frameRect(forContentRect: NSRect(origin: .zero, size: maxContent)).size

        return NSSize(
            width: min(max(frameSize.width, minFrame.width), maxFrame.width),
            height: min(max(frameSize.height, minFrame.height), maxFrame.height)
        )
    }

    func showStickyNote() {
        self.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    var isStickyNoteVisible: Bool {
        self.window?.isVisible ?? false
    }

    func hideStickyNote() {
        self.window?.orderOut(nil)
    }
}
