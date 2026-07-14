import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    static var isTerminating = false

    func application(_: NSApplication, open urls: [URL]) {
        for url in urls {
            PendingOpen.shared.urls.append(url)
        }
        NotificationCenter.default.post(name: .pendingOpenChanged, object: nil)
    }
    
    func applicationShouldTerminate(_: NSApplication) -> NSApplication.TerminateReply {
        AppDelegate.isTerminating = true
        return .terminateNow
    }

    func applicationDidFinishLaunching(_: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        false
    }
}
