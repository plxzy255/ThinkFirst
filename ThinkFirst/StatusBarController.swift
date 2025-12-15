// StatusBarController.swift
// ThinkFirst
// Created for menu bar presentation

import SwiftUI
import AppKit

class StatusBarController {
    private var statusItem: NSStatusItem!
    private var stickyNoteWindowController: StickyNoteWindowController? = nil

    init() {
        stickyNoteWindowController = StickyNoteWindowController()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "globe", accessibilityDescription: "ThinkFirst")
            button.action = #selector(toggleStickyNote)
            button.target = self
        }
    }

    func showStickyNote() {
        stickyNoteWindowController?.showStickyNote()
    }

    func hideStickyNote() {
        stickyNoteWindowController?.hideStickyNote()
    }

    @objc private func toggleStickyNote() {
        guard let controller = stickyNoteWindowController else { return }
        if controller.isStickyNoteVisible {
            controller.hideStickyNote()
        } else {
            controller.showStickyNote()
        }
    }
}
