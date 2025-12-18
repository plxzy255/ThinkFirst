// StickyNoteWindow.swift
// Manages the floating sticky note window and contains the SwiftUI view for editing text.

import AppKit
import CoreLocation
import SwiftUI
import Combine
import QuartzCore

// MARK: - Layout Constants

enum StickyNoteLayout {
    static let contentPadding: CGFloat = 16
    static let contentBottomPaddingWhenPrayerEnabled: CGFloat = 6
    static let fontSize: CGFloat = 18
    static let minVisibleLines: CGFloat = 2
    static let controlsExtraTopPadding: CGFloat = 12
    static let controlsButtonInset: CGFloat = 10
}

// MARK: - Window + Resizing

private final class StickyNoteWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class StickyNoteWindowResizer: ObservableObject {
    private weak var window: NSWindow?

    private var isPrayerEnabled: Bool = false
    private var measuredTextHeight: CGFloat = 0
    private var measuredPrayerHeight: CGFloat = 0
    private var minTextHeight: CGFloat = 0
    private var textTopPadding: CGFloat = 0
    private var textBottomPadding: CGFloat = 0
    private var animateNextApply: Bool = false
    private var nextAnimationDuration: TimeInterval = 0.22
    private var isAnimatingApply: Bool = false
    private var animationTimer: Timer?
    private var animationStartTime: CFTimeInterval = 0
    private var animationDuration: TimeInterval = 0
    private var animationStartFrame: NSRect = .zero
    private var animationTargetFrame: NSRect = .zero
    private var isUserDraggingWindow: Bool = false
    private var needsApplyAfterDrag: Bool = false

    private var lastAppliedContentHeight: CGFloat = 0
    private var pendingApply: Bool = false

    func attach(window: NSWindow) {
        self.window = window
        scheduleApply()
    }

    func setPrayerEnabled(_ enabled: Bool) {
        isPrayerEnabled = enabled
        if enabled, measuredPrayerHeight <= 0 {
            measuredPrayerHeight = 60
        }
        scheduleApply()
    }

    func setMinTextHeight(_ height: CGFloat) {
        minTextHeight = height
        scheduleApply()
    }

    func setTextPadding(top: CGFloat, bottom: CGFloat) {
        if textTopPadding == top, textBottomPadding == bottom { return }
        textTopPadding = top
        textBottomPadding = bottom
        scheduleApply()
    }

    func setMeasuredTextHeight(_ height: CGFloat) {
        measuredTextHeight = height
        scheduleApply()
    }

    func setMeasuredPrayerHeight(_ height: CGFloat) {
        measuredPrayerHeight = height
        scheduleApply()
    }

    func animateNextResize(duration: TimeInterval = 0.22) {
        animateNextApply = true
        nextAnimationDuration = duration
        scheduleApply()
    }

    func finishInFlightAnimationsForUserInteraction() {
        guard isAnimatingApply else { return }
        animationTimer?.invalidate()
        animationTimer = nil
        isAnimatingApply = false
    }

    func beginUserDrag() {
        isUserDraggingWindow = true
        needsApplyAfterDrag = false
        finishInFlightAnimationsForUserInteraction()
    }

    func endUserDrag() {
        isUserDraggingWindow = false
        if needsApplyAfterDrag {
            needsApplyAfterDrag = false
            scheduleApply()
        }
    }

    private func scheduleApply() {
        guard !pendingApply else { return }
        pendingApply = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.pendingApply = false
            self.apply()
        }
    }

    private func apply() {
        guard let window else { return }

        let textHeight = max(measuredTextHeight, minTextHeight)
        let prayerHeight = isPrayerEnabled ? measuredPrayerHeight : 0
        let desiredContentHeight = ceil(textTopPadding + textHeight + textBottomPadding + prayerHeight)

        guard desiredContentHeight.isFinite, desiredContentHeight > 0 else { return }
        guard abs(desiredContentHeight - lastAppliedContentHeight) > 0.5 else { return }

        if isUserDraggingWindow {
            needsApplyAfterDrag = true
            return
        }

        lastAppliedContentHeight = desiredContentHeight

        var newMin = window.contentMinSize
        if newMin.height != desiredContentHeight {
            newMin.height = desiredContentHeight
            window.contentMinSize = newMin
        }

        let currentContentWidth = window.contentRect(forFrameRect: window.frame).width
        let targetContentRect = NSRect(origin: .zero, size: NSSize(width: currentContentWidth, height: desiredContentHeight))
        let targetFrameHeight = window.frameRect(forContentRect: targetContentRect).height

        var frame = window.frame
        let top = frame.maxY
        guard abs(targetFrameHeight - frame.height) > 0.5 else { return }
        frame.size.height = targetFrameHeight
        frame.origin.y = top - targetFrameHeight

        let shouldAnimate = animateNextApply
        let duration = nextAnimationDuration
        animateNextApply = false

        if shouldAnimate {
            startManualResizeAnimation(to: frame, duration: duration)
        } else {
            animationTimer?.invalidate()
            animationTimer = nil
            isAnimatingApply = false
            window.setFrame(frame, display: true, animate: false)
        }
    }

    private func startManualResizeAnimation(to targetFrame: NSRect, duration: TimeInterval) {
        guard let window else { return }

        animationTimer?.invalidate()
        animationTimer = nil

        isAnimatingApply = true
        animationStartTime = CACurrentMediaTime()
        animationDuration = max(0.01, duration)
        animationStartFrame = window.frame
        animationTargetFrame = targetFrame

        let tickInterval: TimeInterval = 1.0 / 60.0
        let timer = Timer(
            timeInterval: tickInterval,
            target: self,
            selector: #selector(handleManualResizeAnimationTick(_:)),
            userInfo: nil,
            repeats: true
        )
        animationTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    @objc private func handleManualResizeAnimationTick(_ timer: Timer) {
        guard let window else {
            timer.invalidate()
            animationTimer = nil
            isAnimatingApply = false
            return
        }

        let elapsed = CACurrentMediaTime() - animationStartTime
        let rawT = min(max(elapsed / animationDuration, 0), 1)
        let t = rawT * rawT * (3 - 2 * rawT)

        let start = animationStartFrame
        let end = animationTargetFrame

        let newX = start.origin.x + (end.origin.x - start.origin.x) * t
        let newY = start.origin.y + (end.origin.y - start.origin.y) * t
        let newW = start.size.width + (end.size.width - start.size.width) * t
        let newH = start.size.height + (end.size.height - start.size.height) * t

        window.setFrame(NSRect(x: newX, y: newY, width: newW, height: newH), display: true, animate: false)

        if rawT >= 1 {
            timer.invalidate()
            animationTimer = nil
            isAnimatingApply = false
        }
    }
}

// MARK: - Native Text Editor

private struct NativeTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool

    var isEditable: Bool
    var font: NSFont
    var textColor: NSColor
    var textContainerInset: CGSize
    var onFocusChange: ((Bool) -> Void)? = nil
    var onEndEditing: (() -> Void)? = nil
    var onMeasuredContentHeight: ((CGFloat) -> Void)? = nil

    private final class NonScrollingMeasuringScrollView: NSScrollView {
        var onLayout: (() -> Void)?
        override func layout() {
            super.layout()
            onLayout?()
        }

        override func scrollWheel(with event: NSEvent) {
            // Never allow internal scrolling; the window grows instead.
        }

        override func reflectScrolledClipView(_ cView: NSClipView) {
            if cView.bounds.origin != .zero {
                cView.scroll(to: .zero)
            }
            super.reflectScrolledClipView(cView)
        }
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NonScrollingMeasuringScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.verticalScrollElasticity = .none
        scrollView.horizontalScrollElasticity = .none

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
        unsafe textView.textContainer?.lineFragmentPadding = 0
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        unsafe textView.textContainer?.widthTracksTextView = true
        unsafe textView.textContainer?.heightTracksTextView = false

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
            guard let scrollView, let textView else { return }
            let measured = Self.measuredContentHeight(for: textView)
            DispatchQueue.main.async {
                guard unsafe scrollView.window != nil else { return }
                onMeasuredContentHeight?(measured)
            }
        }

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? CallbackTextView else { return }

        if textView.string != text { textView.string = text }
        if textView.isEditable != isEditable { textView.isEditable = isEditable }
        if textView.isSelectable != isEditable { textView.isSelectable = isEditable }
        if textView.font != font { textView.font = font }
        if textView.textColor != textColor { textView.textColor = textColor }

        let inset = NSSize(width: textContainerInset.width, height: textContainerInset.height)
        if textView.textContainerInset != inset { textView.textContainerInset = inset }
        unsafe textView.textContainer?.lineFragmentPadding = 0
        unsafe textView.textContainer?.widthTracksTextView = true
        unsafe textView.textContainer?.heightTracksTextView = false

        let requiredHeight = Self.measuredContentHeight(for: textView)
        let contentSize = nsView.contentSize

        var frame = textView.frame
        frame.size.width = contentSize.width
        frame.size.height = max(contentSize.height, requiredHeight)
        if textView.frame != frame { textView.frame = frame }

        // Ensure programmatic text changes (e.g. trimming trailing newlines on end editing)
        // still trigger a resize even if no layout pass occurs.
        onMeasuredContentHeight?(requiredHeight)

        if isFocused {
            let window = unsafe nsView.window
            if window?.firstResponder !== textView {
                window?.makeFirstResponder(textView)
            }
        } else {
            let window = unsafe nsView.window
            if window?.firstResponder === textView {
                window?.makeFirstResponder(nil)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onMeasuredContentHeight: onMeasuredContentHeight)
    }

    private static func measuredContentHeight(for textView: NSTextView) -> CGFloat {
        let textContainer = unsafe textView.textContainer
        let layoutManager = unsafe textView.layoutManager
        guard let textContainer, let layoutManager else {
            return max(0, textView.bounds.height)
        }

        layoutManager.ensureLayout(for: textContainer)
        let usedHeight = layoutManager.usedRect(for: textContainer).height
        let font = textView.font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let lineHeight = layoutManager.defaultLineHeight(for: font)
        return ceil(max(usedHeight, lineHeight))
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        private let onMeasuredContentHeight: ((CGFloat) -> Void)?

        init(text: Binding<String>, onMeasuredContentHeight: ((CGFloat) -> Void)?) {
            _text = text
            self.onMeasuredContentHeight = onMeasuredContentHeight
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text = textView.string
            onMeasuredContentHeight?(NativeTextView.measuredContentHeight(for: textView))
        }
    }

    final class CallbackTextView: NSTextView {
        var onFocusChange: (Bool) -> Void = { _ in }
        var onEndEditing: () -> Void = {}
        private weak var observedWindow: NSWindow?

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

            if let observedWindow {
                NotificationCenter.default.removeObserver(self, name: NSWindow.didResignKeyNotification, object: observedWindow)
            }
            NotificationCenter.default.removeObserver(self, name: NSApplication.didResignActiveNotification, object: NSApp)
            observedWindow = nil

            guard let window = unsafe self.window else { return }
            observedWindow = window

            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleWindowDidResignKey(_:)),
                name: NSWindow.didResignKeyNotification,
                object: window
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleAppDidResignActive(_:)),
                name: NSApplication.didResignActiveNotification,
                object: NSApp
            )
        }

        @objc private func handleWindowDidResignKey(_ notification: Notification) {
            onEndEditing()
        }

        @objc private func handleAppDidResignActive(_ notification: Notification) {
            onEndEditing()
        }
    }
}

// MARK: - Window Dragging Overlay

private struct WindowDragOverlay: NSViewRepresentable {
    var enabled: Bool
    var onDragStart: () -> Void = {}
    var onDragEnd: () -> Void = {}
    var onDoubleClick: () -> Void

    func makeNSView(context: Context) -> DragOverlayView {
        let view = DragOverlayView()
        view.enabled = enabled
        view.onDragStart = onDragStart
        view.onDragEnd = onDragEnd
        view.onDoubleClick = onDoubleClick
        return view
    }

    func updateNSView(_ nsView: DragOverlayView, context: Context) {
        nsView.enabled = enabled
        nsView.onDragStart = onDragStart
        nsView.onDragEnd = onDragEnd
        nsView.onDoubleClick = onDoubleClick
    }

    final class DragOverlayView: NSView {
        var enabled: Bool = false
        var onDragStart: () -> Void = {}
        var onDragEnd: () -> Void = {}
        var onDoubleClick: () -> Void = {}
        private var dragStarted: Bool = false
        private var dragStartMouseScreenPoint: NSPoint = .zero
        private var dragStartWindowOrigin: NSPoint = .zero
        private var mouseDownWindowFrame: NSRect = .zero

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
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
	
	            dragStarted = false
	            let window = unsafe self.window
	            if let window {
	                mouseDownWindowFrame = window.frame
	                dragStartWindowOrigin = mouseDownWindowFrame.origin
	                dragStartMouseScreenPoint = window.convertPoint(toScreen: event.locationInWindow)
	
                // If the window is currently inactive, activation/resizing can kick off immediately after mouseDown.
                // Start a "drag session" now so the resizer can defer any frame changes until mouseUp.
                if !window.isKeyWindow {
                    dragStarted = true
                    onDragStart()
                    mouseDownWindowFrame = window.frame
                    dragStartWindowOrigin = mouseDownWindowFrame.origin
                }
            }
	        }
	
	        override func mouseDragged(with event: NSEvent) {
	            guard enabled, let window = unsafe self.window else {
	                super.mouseDragged(with: event)
	                return
	            }

            let currentMouseScreenPoint = window.convertPoint(toScreen: event.locationInWindow)

            if !dragStarted {
                dragStarted = true
                onDragStart()
                // If the window resized/repositioned between mouseDown and the first mouseDragged (activation),
                // reset baseline to avoid a jump.
                if window.frame != mouseDownWindowFrame {
                    mouseDownWindowFrame = window.frame
                    dragStartWindowOrigin = mouseDownWindowFrame.origin
                    dragStartMouseScreenPoint = currentMouseScreenPoint
                }
            }

            let dx = currentMouseScreenPoint.x - dragStartMouseScreenPoint.x
            let dy = currentMouseScreenPoint.y - dragStartMouseScreenPoint.y
            let newOrigin = NSPoint(x: dragStartWindowOrigin.x + dx, y: dragStartWindowOrigin.y + dy)
            let scale = max(1, window.backingScaleFactor)
            let snapped = NSPoint(
                x: (newOrigin.x * scale).rounded() / scale,
                y: (newOrigin.y * scale).rounded() / scale
            )
            window.setFrameOrigin(snapped)
        }

        override func mouseUp(with event: NSEvent) {
            defer { dragStarted = false }
            guard enabled else {
                super.mouseUp(with: event)
                return
            }

            if dragStarted {
                onDragEnd()
            }
        }
    }
}

// MARK: - SwiftUI Content

private struct PrayerAccessoryHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

// The content that appears in the sticky note window
struct StickyNoteView: View {
    @StateObject private var resizer: StickyNoteWindowResizer

    @AppStorage("stickyNoteText") private var text: String = ""
    @AppStorage("stickyNoteInactiveBackgroundOpacity") private var inactiveBackgroundOpacity: Double = 0.14
    @AppStorage("prayerEnabled") private var prayerEnabled: Bool = false

    @State private var isEditing: Bool = false
    @State private var isTextEditorFocused: Bool = false
    @State private var isPrayerAccessoryVisible: Bool = false

    @Environment(\.controlActiveState) private var controlActiveState

    @ObservedObject private var prayerLocationManager = PrayerLocationManager.shared
    private let editorFont: NSFont = .systemFont(ofSize: StickyNoteLayout.fontSize)

    private var editorLineHeight: CGFloat {
        editorFont.ascender + abs(editorFont.descender) + editorFont.leading
    }

    private var minTextContentHeight: CGFloat {
        let lineHeight = ceil(editorLineHeight)
        return ceil(lineHeight * StickyNoteLayout.minVisibleLines)
    }

    private var isWindowActive: Bool { controlActiveState == .key }

    init(resizer: StickyNoteWindowResizer = StickyNoteWindowResizer(), previewIsEditing: Bool = false) {
        _resizer = StateObject(wrappedValue: resizer)
        _isEditing = State(initialValue: previewIsEditing)
        _isTextEditorFocused = State(initialValue: previewIsEditing)
    }

    var body: some View {
        let controlsAreVisible = isEditing || (isWindowActive && !isEditing)
        let textTopPadding = StickyNoteLayout.contentPadding + (controlsAreVisible ? StickyNoteLayout.controlsExtraTopPadding : 0)
        let textBottomPadding = prayerEnabled ? StickyNoteLayout.contentBottomPaddingWhenPrayerEnabled : StickyNoteLayout.contentPadding

        VStack(spacing: 0) {
            NativeTextView(
                text: $text,
                isFocused: $isTextEditorFocused,
                isEditable: isEditing,
                font: editorFont,
                textColor: .white,
                textContainerInset: .zero,
                onFocusChange: { focused in
                    if !focused { endEditing() }
                },
                onEndEditing: {
                    endEditing()
                },
                onMeasuredContentHeight: { measuredContentHeight in
                    resizer.setMeasuredTextHeight(measuredContentHeight)
                }
            )
            .padding(.top, textTopPadding)
            .padding(.bottom, textBottomPadding)
            .padding(.leading, StickyNoteLayout.contentPadding)
            .padding(.trailing, StickyNoteLayout.contentPadding)
            .layoutPriority(1)

            if prayerEnabled, isPrayerAccessoryVisible {
                prayerAccessoryView
                    .background {
                        GeometryReader { proxy in
                            Color.clear
                                .preference(key: PrayerAccessoryHeightPreferenceKey.self, value: proxy.size.height)
                        }
                    }
            }
        }
        .animation(.easeInOut(duration: 0.22), value: controlsAreVisible)
        .onPreferenceChange(PrayerAccessoryHeightPreferenceKey.self) { height in
            resizer.setMeasuredPrayerHeight(height)
        }
        .onAppear {
            resizer.setMinTextHeight(minTextContentHeight)
            resizer.setTextPadding(top: textTopPadding, bottom: textBottomPadding)
            resizer.setPrayerEnabled(prayerEnabled)
            if prayerEnabled {
                isPrayerAccessoryVisible = false
                DispatchQueue.main.async {
                    isPrayerAccessoryVisible = true
                }
                prayerLocationManager.requestAccessAndLocation()
            } else {
                isPrayerAccessoryVisible = false
            }
        }
        .onChange(of: isEditing) { _, _ in
            resizer.animateNextResize()
            resizer.setTextPadding(top: textTopPadding, bottom: textBottomPadding)
        }
        .onChange(of: controlActiveState) { oldState, newState in
            if oldState != newState, !isEditing {
                resizer.animateNextResize()
            }
            resizer.setTextPadding(top: textTopPadding, bottom: textBottomPadding)
        }
        .onChange(of: prayerEnabled) { _, enabled in
            if enabled {
                isPrayerAccessoryVisible = false
                DispatchQueue.main.async {
                    isPrayerAccessoryVisible = true
                }
            } else {
                isPrayerAccessoryVisible = false
            }
            resizer.setPrayerEnabled(enabled)
            resizer.setTextPadding(top: textTopPadding, bottom: textBottomPadding)
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
            WindowDragOverlay(
                enabled: !isEditing,
                onDragStart: { resizer.beginUserDrag() },
                onDragEnd: { resizer.endUserDrag() }
            ) {
                isEditing = true
                DispatchQueue.main.async {
                    isTextEditorFocused = true
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            if isEditing {
                doneButton
                    .padding(.top, StickyNoteLayout.controlsButtonInset)
                    .padding(.trailing, StickyNoteLayout.controlsButtonInset)
            } else if isWindowActive {
                settingsButton
                    .padding(.top, StickyNoteLayout.controlsButtonInset)
                    .padding(.trailing, StickyNoteLayout.controlsButtonInset)
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
                    .padding(.vertical, 8)
                    .padding(.horizontal, StickyNoteLayout.contentPadding)
            }
        }
    }

    private var prayerLocationPlaceholderText: String {
        switch prayerLocationManager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            return "Getting location…"
        case .notDetermined:
            return "Allow location access in Settings to show prayer times."
        case .restricted, .denied:
            return "Location access is off. Enable it in System Settings to show prayer times."
        @unknown default:
            return "Location status unknown."
        }
    }

    private var doneButton: some View {
        Button {
            endEditing()
        } label: {
            Label("Done", systemImage: "checkmark.circle.fill")
                .labelStyle(.iconOnly)
        }
        .buttonStyle(.borderless)
        .controlSize(.regular)
        .tint(.accentColor)
        .accessibilityLabel("Done")
    }

    private var settingsButton: some View {
        Button {
            SettingsPanelController.shared.show()
        } label: {
            Label("Settings", systemImage: "ellipsis.circle")
                .labelStyle(.iconOnly)
        }
        .buttonStyle(.borderless)
        .controlSize(.regular)
        .accessibilityLabel("Settings")
    }

    private func endEditing() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed != text { text = trimmed }

        isTextEditorFocused = false
        isEditing = false
    }
}

// MARK: - Window Controller

final class StickyNoteWindowController: NSWindowController, NSWindowDelegate {
    private static let minWidth: CGFloat = 260
    private static let maxWidth: CGFloat = 520

    private let resizer = StickyNoteWindowResizer()

    init() {
        let hosting = NSHostingController(rootView: StickyNoteView(resizer: resizer))
        hosting.sizingOptions = []

        let window = StickyNoteWindow(contentViewController: hosting)
        window.title = "Sticky Note"

        let font = NSFont.systemFont(ofSize: StickyNoteLayout.fontSize)
        let lineHeight = ceil(font.ascender + abs(font.descender) + font.leading)
        let minHeight = ceil(StickyNoteLayout.contentPadding * 2 + lineHeight * StickyNoteLayout.minVisibleLines)

        window.setContentSize(NSSize(width: Self.minWidth, height: minHeight))
        window.contentMinSize = NSSize(width: Self.minWidth, height: minHeight)
        window.contentMaxSize = NSSize(width: Self.maxWidth, height: .greatestFiniteMagnitude)

        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.styleMask = [.borderless, .resizable, .fullSizeContentView]
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenNone]
        window.isOpaque = false
        window.backgroundColor = .clear

        super.init(window: window)

        window.delegate = self
        resizer.attach(window: window)
    }

    required init?(coder: NSCoder) { super.init(coder: coder) }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        let minContent = NSSize(width: Self.minWidth, height: 1)
        let maxContent = NSSize(width: Self.maxWidth, height: 1)

        let minFrameWidth = sender.frameRect(forContentRect: NSRect(origin: .zero, size: minContent)).width
        let maxFrameWidth = sender.frameRect(forContentRect: NSRect(origin: .zero, size: maxContent)).width

        let clampedWidth = min(max(frameSize.width, minFrameWidth), maxFrameWidth)
        let lockedHeight = sender.frame.size.height

        return NSSize(width: clampedWidth, height: lockedHeight)
    }

    func showStickyNote() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    var isStickyNoteVisible: Bool {
        window?.isVisible ?? false
    }

    func hideStickyNote() {
        window?.orderOut(nil)
    }
}
