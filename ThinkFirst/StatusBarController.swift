// StatusBarController.swift
// ThinkFirst
// Created for menu bar presentation

import SwiftUI
import AppKit

final class SettingsPanelController: NSWindowController {
    static let shared = SettingsPanelController()

    init() {
        let hostingView = NSHostingView(rootView: ThinkFirstSettingsView())
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 452, height: 320),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "Settings"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.isReleasedWhenClosed = false
        panel.contentView = hostingView
        panel.center()

        super.init(window: panel)
    }

    required init?(coder: NSCoder) { super.init(coder: coder) }

    func show() {
        guard let window else { return }
        NSApp.activate(ignoringOtherApps: true)
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
    }
}

final class StatusBarController: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var stickyNoteWindowController: StickyNoteWindowController? = nil
    private let statusMenu = NSMenu()
    private let toggleVisibilityItem = NSMenuItem()

    override init() {
        super.init()
        stickyNoteWindowController = StickyNoteWindowController()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "globe", accessibilityDescription: "ThinkFirst")
        }

        statusMenu.delegate = self
        toggleVisibilityItem.target = self
        toggleVisibilityItem.action = #selector(toggleStickyNoteFromMenu)
        statusMenu.addItem(toggleVisibilityItem)

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.keyEquivalentModifierMask = [.command]
        settingsItem.target = self
        statusMenu.addItem(settingsItem)

        statusMenu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.keyEquivalentModifierMask = [.command]
        quitItem.target = self
        statusMenu.addItem(quitItem)

        updateToggleVisibilityTitle()
        statusItem.menu = statusMenu
    }

    func showStickyNote() {
        stickyNoteWindowController?.showStickyNote()
    }

    func hideStickyNote() {
        stickyNoteWindowController?.hideStickyNote()
    }

    func menuWillOpen(_ menu: NSMenu) {
        updateToggleVisibilityTitle()
    }

    private func updateToggleVisibilityTitle() {
        guard let controller = stickyNoteWindowController else {
            toggleVisibilityItem.title = "Show"
            return
        }
        toggleVisibilityItem.title = controller.isStickyNoteVisible ? "Hide" : "Show"
    }

    @objc private func toggleStickyNoteFromMenu() {
        guard let controller = stickyNoteWindowController else { return }
        if controller.isStickyNoteVisible {
            controller.hideStickyNote()
        } else {
            controller.showStickyNote()
        }
        updateToggleVisibilityTitle()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    @objc private func showSettings() {
        // Showing a window while the status bar menu is tracking can fail to reveal it reliably.
        // Defer to the next run loop so the menu has closed first.
        DispatchQueue.main.async {
            SettingsPanelController.shared.show()
        }
    }
}
