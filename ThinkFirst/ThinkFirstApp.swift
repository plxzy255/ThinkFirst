//
//  ThinkFirstApp.swift
//  ThinkFirst
//
//  Created by psporidi on 15/12/2025.
//

import SwiftUI
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusBarController: StatusBarController?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            return
        }
        statusBarController = StatusBarController()
        DispatchQueue.main.async { [weak self] in
            self?.statusBarController?.showStickyNote()
        }
    }
}

@main
struct ThinkFirstApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene {
        Settings {}
    }
}
