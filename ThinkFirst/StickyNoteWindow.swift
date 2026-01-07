// StickyNoteWindow.swift
// Manages the floating sticky note window and contains the SwiftUI view for editing text.

import AppKit
import CoreLocation
import PrayerKit
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

enum StickyNoteFontSizeOption: String, CaseIterable, Identifiable {
    static let storageKey: String = "stickyNoteFontSizeOption"

    case small
    case normal
    case large
    case extraLarge

    var id: String { rawValue }

    var title: String {
        switch self {
        case .small: "Small"
        case .normal: "Normal"
        case .large: "Large"
        case .extraLarge: "Extra Large"
        }
    }

    var scale: CGFloat {
        switch self {
        case .small: 0.85
        case .normal: 1.00
        case .large: 1.20
        case .extraLarge: 1.35
        }
    }

    static func from(rawValue: String) -> StickyNoteFontSizeOption {
        StickyNoteFontSizeOption(rawValue: rawValue) ?? .normal
    }
}

// MARK: - Window + Resizing

private final class StickyNoteWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// MARK: - Visual Effect Wrapper for Inactive State

private struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    
    init(material: NSVisualEffectView.Material = .windowBackground, blendingMode: NSVisualEffectView.BlendingMode = .behindWindow) {
        self.material = material
        self.blendingMode = blendingMode
    }
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = .active
    }
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
        guard height.isFinite else { return }
        if abs(measuredTextHeight - height) <= 0.5 { return }
        measuredTextHeight = height
        scheduleApply()
    }

    func setMeasuredPrayerHeight(_ height: CGFloat) {
        guard height.isFinite else { return }
        if abs(measuredPrayerHeight - height) <= 0.5 { return }
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

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? CallbackTextView else { return }

        var needsRemeasure = false

        if textView.string != text {
            textView.string = text
            needsRemeasure = true
        }
        if textView.isEditable != isEditable { textView.isEditable = isEditable }
        if textView.isSelectable != isEditable { textView.isSelectable = isEditable }
        if textView.font != font {
            textView.font = font
            needsRemeasure = true
        }
        if textView.textColor != textColor { textView.textColor = textColor }

        let inset = NSSize(width: textContainerInset.width, height: textContainerInset.height)
        if textView.textContainerInset != inset {
            textView.textContainerInset = inset
            needsRemeasure = true
        }
        unsafe textView.textContainer?.lineFragmentPadding = 0
        unsafe textView.textContainer?.widthTracksTextView = true
        unsafe textView.textContainer?.heightTracksTextView = false

        let contentSize = nsView.contentSize

        var frame = textView.frame
        let backingScaleFactor = (unsafe nsView.window?.backingScaleFactor) ?? NSScreen.main?.backingScaleFactor ?? 2
        let roundedWidth = (contentSize.width * backingScaleFactor).rounded() / backingScaleFactor
        frame.size.width = roundedWidth

        let requiredHeight = context.coordinator.requiredHeight(
            for: textView,
            availableWidth: roundedWidth,
            forceRemeasure: needsRemeasure
        )
        frame.size.height = max(contentSize.height, requiredHeight)
        if textView.frame != frame { textView.frame = frame }

        // Avoid measuring/reporting continuously during unrelated SwiftUI updates (e.g. tint opacity animations).
        context.coordinator.reportMeasuredHeightIfNeeded(requiredHeight)

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
        let insetHeight = textView.textContainerInset.height * 2
        // AppKit occasionally under-reports the used height by a fraction of a point for larger fonts,
        // which can clip descenders by ~1px. Add a tiny, font-relative padding to avoid clipping.
        let measurementPadding = max(1, ceil(font.pointSize * 0.17))
        return ceil(max(usedHeight, lineHeight) + insetHeight + measurementPadding)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        private let onMeasuredContentHeight: ((CGFloat) -> Void)?
        private var lastReportedMeasuredHeight: CGFloat = -1
        private var lastMeasuredWidth: CGFloat = -1
        private var lastMeasuredFontPointSize: CGFloat = -1
        private var lastMeasuredInset: NSSize = NSSize(width: -1, height: -1)
        private var cachedMeasuredHeight: CGFloat = -1

        init(text: Binding<String>, onMeasuredContentHeight: ((CGFloat) -> Void)?) {
            _text = text
            self.onMeasuredContentHeight = onMeasuredContentHeight
        }

        func requiredHeight(for textView: NSTextView, availableWidth: CGFloat, forceRemeasure: Bool) -> CGFloat {
            let fontPointSize = textView.font?.pointSize ?? NSFont.systemFontSize
            let inset = textView.textContainerInset

            let widthChanged = abs(lastMeasuredWidth - availableWidth) > 0.5
            let fontChanged = abs(lastMeasuredFontPointSize - fontPointSize) > 0.01
            let insetChanged = lastMeasuredInset != inset

            if forceRemeasure || widthChanged || fontChanged || insetChanged || cachedMeasuredHeight < 0 {
                lastMeasuredWidth = availableWidth
                lastMeasuredFontPointSize = fontPointSize
                lastMeasuredInset = inset
                cachedMeasuredHeight = NativeTextView.measuredContentHeight(for: textView)
            }

            if cachedMeasuredHeight.isFinite, cachedMeasuredHeight >= 0 {
                return cachedMeasuredHeight
            }
            return 0
        }

        func reportMeasuredHeightIfNeeded(_ height: CGFloat) {
            guard height.isFinite else { return }
            guard abs(lastReportedMeasuredHeight - height) > 0.5 else { return }
            lastReportedMeasuredHeight = height
            onMeasuredContentHeight?(height)
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text = textView.string
            cachedMeasuredHeight = NativeTextView.measuredContentHeight(for: textView)
            reportMeasuredHeightIfNeeded(cachedMeasuredHeight)
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
    @AppStorage(StickyNoteFontSizeOption.storageKey) private var stickyNoteFontSizeOptionRaw: String = StickyNoteFontSizeOption.normal.rawValue
    @AppStorage("prayerEnabled") private var prayerEnabled: Bool = false
    @AppStorage("prayerAlertEnabled") private var prayerAlertEnabled: Bool = false
    @AppStorage("prayerAlertTestNonce") private var prayerAlertTestNonce: Int = 0

    @State private var isEditing: Bool = false
    @State private var isTextEditorFocused: Bool = false
    @State private var isPrayerAccessoryVisible: Bool = false
    @State private var isPrayerAlertTintVisible: Bool = false
    @State private var prayerAlertResetTask: Task<Void, Never>?

    @Environment(\.controlActiveState) private var controlActiveState

    private var fontScale: CGFloat {
        StickyNoteFontSizeOption.from(rawValue: stickyNoteFontSizeOptionRaw).scale
    }

    private var editorFont: NSFont {
        .systemFont(ofSize: StickyNoteLayout.fontSize * fontScale)
    }

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
            } else {
                isPrayerAccessoryVisible = false
            }
        }
        .onDisappear {
            prayerAlertResetTask?.cancel()
            prayerAlertResetTask = nil
            isPrayerAlertTintVisible = false
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
        }
        .onChange(of: stickyNoteFontSizeOptionRaw) { _, _ in
            resizer.setMinTextHeight(minTextContentHeight)
            resizer.animateNextResize()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            Color.clear
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay { alertTintOverlay }
        .overlay { dragOverlay }
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
        .onChange(of: prayerAlertTestNonce) { _, _ in triggerPrayerAlertPulse() }
    }

    private var alertTintOverlay: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(Color.yellow)
            .opacity(isPrayerAlertTintVisible ? 0.14 : 0)
            .allowsHitTesting(false)
    }

    private var dragOverlay: some View {
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

    private var prayerAccessoryView: some View {
        PrayerAccessoryView(
            enabled: prayerEnabled,
            alertsEnabled: prayerAlertEnabled,
            fontScale: fontScale,
            horizontalPadding: StickyNoteLayout.contentPadding
        ) {
            triggerPrayerAlertPulse()
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
        SettingsLink {
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

    private func triggerPrayerAlertPulse() {
        guard prayerEnabled, prayerAlertEnabled else { return }

        prayerAlertResetTask?.cancel()
        prayerAlertResetTask = Task { @MainActor in
            let pulseCount = 3
            let pulseDuration: TimeInterval = 0.9

            isPrayerAlertTintVisible = false

            for _ in 0..<pulseCount {
                if Task.isCancelled { return }
                withAnimation(.easeInOut(duration: pulseDuration)) {
                    isPrayerAlertTintVisible = true
                }
                try? await Task.sleep(nanoseconds: UInt64(pulseDuration * 1_000_000_000))

                if Task.isCancelled { return }
                withAnimation(.easeInOut(duration: pulseDuration)) {
                    isPrayerAlertTintVisible = false
                }
                try? await Task.sleep(nanoseconds: UInt64(pulseDuration * 1_000_000_000))
            }

            isPrayerAlertTintVisible = false
        }
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
        
        let effectView = NSVisualEffectView()
        effectView.material = .hudWindow
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = 16
        effectView.layer?.masksToBounds = true
        
        let overlayView = NSView()
        overlayView.wantsLayer = true
        overlayView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.5).cgColor
        overlayView.alphaValue = 0
        overlayView.identifier = NSUserInterfaceItemIdentifier("transparencyOverlay")
        
        effectView.addSubview(overlayView)
        overlayView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            overlayView.topAnchor.constraint(equalTo: effectView.topAnchor),
            overlayView.leadingAnchor.constraint(equalTo: effectView.leadingAnchor),
            overlayView.trailingAnchor.constraint(equalTo: effectView.trailingAnchor),
            overlayView.bottomAnchor.constraint(equalTo: effectView.bottomAnchor)
        ])
        
        hosting.view.removeFromSuperview()
        effectView.addSubview(hosting.view)
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hosting.view.topAnchor.constraint(equalTo: effectView.topAnchor),
            hosting.view.leadingAnchor.constraint(equalTo: effectView.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: effectView.trailingAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: effectView.bottomAnchor)
        ])
        
        window.contentView = effectView

        let storedFontOptionRaw = UserDefaults.standard.string(forKey: StickyNoteFontSizeOption.storageKey) ?? StickyNoteFontSizeOption.normal.rawValue
        let storedFontScale = StickyNoteFontSizeOption.from(rawValue: storedFontOptionRaw).scale
        let font = NSFont.systemFont(ofSize: StickyNoteLayout.fontSize * storedFontScale)
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
        
        UserDefaults.standard.addObserver(self, forKeyPath: "stickyNoteInactiveBackgroundOpacity", options: [.new], context: nil)
    }
    
    nonisolated override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == "stickyNoteInactiveBackgroundOpacity" {
            Task { @MainActor in
                if window?.isKeyWindow == false {
                    updateOverlayAlpha(isKey: false)
                }
            }
        }
    }

    required init?(coder: NSCoder) { super.init(coder: coder) }
    
    func windowDidBecomeKey(_ notification: Notification) {
        updateOverlayAlpha(isKey: true)
    }
    
    func windowDidResignKey(_ notification: Notification) {
        updateOverlayAlpha(isKey: false)
    }
    
    private func updateOverlayAlpha(isKey: Bool) {
        guard let win = window,
              let contentView = win.contentView else { return }
        
        for subview in contentView.subviews {
            if subview.identifier == NSUserInterfaceItemIdentifier("transparencyOverlay") {
                if isKey {
                    subview.alphaValue = 0
                } else {
                    let opacity = UserDefaults.standard.double(forKey: "stickyNoteInactiveBackgroundOpacity")
                    subview.alphaValue = CGFloat(opacity)
                }
                return
            }
        }
    }
    
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
