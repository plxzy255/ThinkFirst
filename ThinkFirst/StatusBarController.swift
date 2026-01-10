// StatusBarController.swift
// ThinkFirst
// Created for menu bar presentation

import SwiftUI
import AppKit

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

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
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

    @objc private func openSettings() {
        Task { @MainActor in
            if let mainMenu = NSApp.mainMenu {
                for menu in mainMenu.items {
                    if let submenu = menu.submenu {
                        for item in submenu.items {
                            if item.title.contains("Settings") || item.title.contains("Preferences") {
                                if let action = item.action {
                                    NSApp.sendAction(action, to: item.target, from: nil)
                                }
                                return
                            }
                        }
                    }
                }
            }
        }
    }
}
