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
    private let backgroundMenuItem = NSMenuItem(title: "Background", action: nil, keyEquivalent: "")
    private let backgroundSubmenu = NSMenu()
    private let backgroundSolidItem = NSMenuItem(title: "Solid", action: #selector(setBackgroundSolid), keyEquivalent: "")
    private let backgroundLiquidGlassItem = NSMenuItem(title: "Liquid Glass", action: #selector(setBackgroundLiquidGlass), keyEquivalent: "")

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
        statusMenu.addItem(.separator())

        backgroundSolidItem.target = self
        backgroundLiquidGlassItem.target = self
        backgroundSubmenu.addItem(backgroundSolidItem)
        backgroundSubmenu.addItem(backgroundLiquidGlassItem)
        backgroundMenuItem.submenu = backgroundSubmenu
        statusMenu.addItem(backgroundMenuItem)
        statusMenu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.keyEquivalentModifierMask = [.command]
        quitItem.target = self
        statusMenu.addItem(quitItem)

        updateToggleVisibilityTitle()
        updateBackgroundMenuState()
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
        updateBackgroundMenuState()
    }

    private func updateToggleVisibilityTitle() {
        guard let controller = stickyNoteWindowController else {
            toggleVisibilityItem.title = "Show"
            return
        }
        toggleVisibilityItem.title = controller.isStickyNoteVisible ? "Hide" : "Show"
    }

    private func updateBackgroundMenuState() {
        let currentRaw = UserDefaults.standard.string(forKey: "stickyNoteBackgroundStyle")
            ?? StickyNoteBackgroundStyle.solid.rawValue
        let current = StickyNoteBackgroundStyle(rawValue: currentRaw) ?? .solid

        backgroundSolidItem.state = (current == .solid) ? .on : .off
        backgroundLiquidGlassItem.state = (current == .liquidGlass) ? .on : .off
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

    @objc private func setBackgroundSolid() {
        UserDefaults.standard.set(StickyNoteBackgroundStyle.solid.rawValue, forKey: "stickyNoteBackgroundStyle")
        updateBackgroundMenuState()
    }

    @objc private func setBackgroundLiquidGlass() {
        UserDefaults.standard.set(StickyNoteBackgroundStyle.liquidGlass.rawValue, forKey: "stickyNoteBackgroundStyle")
        updateBackgroundMenuState()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
