import Cocoa
import SwiftUI
import Combine

class TwitterWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

class TwitterWindowController: NSWindowController {

    private var service = TwitterService.shared
    private var cancellables = Set<AnyCancellable>()
    private var rotationTimer: Timer?

    // State
    @Published var currentBookmark: TwitterBookmark?

    init() {
        // Create the window
        let window = TwitterWindow(
            contentRect: NSRect(x: 0, y: 0, width: 350, height: 200),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Twitter Widget"
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenNone]
        window.isMovableByWindowBackground = true // Allow dragging

        super.init(window: window)

        // Setup Content View
        let contentView = TwitterWidgetWrapper(controller: self)
        window.contentView = NSHostingView(rootView: contentView)

        setupBindings()
        startRotationTimer()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupBindings() {
        service.$bookmarks
            .sink { [weak self] bookmarks in
                if self?.currentBookmark == nil {
                    self?.rotateBookmark()
                }
            }
            .store(in: &cancellables)
    }

    private func startRotationTimer() {
        // Rotate every 2 hours (7200 seconds)
        rotationTimer = Timer.scheduledTimer(withTimeInterval: 7200, repeats: true) { [weak self] _ in
            self?.rotateBookmark()
        }
    }

    func rotateBookmark() {
        guard !service.bookmarks.isEmpty else { return }
        let randomIndex = Int.random(in: 0..<service.bookmarks.count)
        DispatchQueue.main.async {
            self.currentBookmark = self.service.bookmarks[randomIndex]
            // Allow layout pass to occur
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.resizeWindowToFitContent()
            }
        }
    }

    func resizeWindowToFitContent() {
        guard let window = window, let view = window.contentView else { return }
        var frame = window.frame
        let fittingSize = view.fittingSize

        // Ensure minimal height
        let newHeight = max(fittingSize.height, 100)

        if frame.size.height != newHeight {
            frame.size.height = newHeight
            // Adjust origin to keep top-left constant-ish or just setFrame
            window.setFrame(frame, display: true, animate: true)
        }
    }

    func show() {
        window?.makeKeyAndOrderFront(nil)
    }

    func hide() {
        window?.orderOut(nil)
    }

    var isVisible: Bool {
        return window?.isVisible ?? false
    }
}

struct TwitterWidgetWrapper: View {
    @ObservedObject var controller: TwitterWindowController

    var body: some View {
        if let bookmark = controller.currentBookmark {
            TwitterWidgetView(bookmark: bookmark)
                .onTapGesture(count: 2) {
                    controller.rotateBookmark()
                }
        } else {
            // Placeholder or Empty State
            Text("No Bookmarks Loaded")
                .padding()
                .background(.ultraThinMaterial)
                .cornerRadius(12)
                .onTapGesture {
                    controller.rotateBookmark()
                }
        }
    }
}
