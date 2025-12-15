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
            button.action = #selector(showStickyNote)
            button.target = self
        }
    }

    @objc private func showStickyNote() {
        stickyNoteWindowController?.showStickyNote()
    }
}

