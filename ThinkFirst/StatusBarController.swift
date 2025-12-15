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
    private let opacityMenuItem = NSMenuItem(title: "Opacity", action: nil, keyEquivalent: "")
    private let opacityViewController = OpacityMenuItemController()

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

        opacityMenuItem.view = opacityViewController.view
        statusMenu.addItem(opacityMenuItem)
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
        opacityViewController.syncFromDefaults()
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

private final class OpacityMenuItemController {
    let view: NSView
    private let slider: NSSlider
    private let valueLabel: NSTextField

    init() {
        slider = NSSlider(value: 0.7, minValue: 0.0, maxValue: 1.0, target: nil, action: nil)
        slider.isContinuous = true

        valueLabel = NSTextField(labelWithString: "")
        valueLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        valueLabel.textColor = .secondaryLabelColor
        valueLabel.alignment = .right

        let titleLabel = NSTextField(labelWithString: "Opacity")
        titleLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        titleLabel.textColor = .secondaryLabelColor

        let header = NSStackView(views: [titleLabel, valueLabel])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.distribution = .fill

        let stack = NSStackView(views: [header, slider])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6

        view = NSView(frame: NSRect(x: 0, y: 0, width: 220, height: 44))
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -8),
        ])

        slider.target = self
        slider.action = #selector(sliderChanged(_:))

        syncFromDefaults()
    }

    func syncFromDefaults() {
        let stored = UserDefaults.standard.object(forKey: "stickyNoteBackgroundOpacity") as? Double
        let value = stored ?? 0.7
        slider.doubleValue = value
        updateValueLabel(value)
    }

    @objc private func sliderChanged(_ sender: NSSlider) {
        let value = sender.doubleValue
        UserDefaults.standard.set(value, forKey: "stickyNoteBackgroundOpacity")
        updateValueLabel(value)
    }

    private func updateValueLabel(_ value: Double) {
        valueLabel.stringValue = "\(Int((value * 100).rounded()))%"
    }
}
