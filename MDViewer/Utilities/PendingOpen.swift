//
//  PendingOpen.swift
//  MDViewer
//
//  Created by Matt Braunstein on 7/12/26.
//

import Foundation

@MainActor
final class PendingOpen {
    static let shared = PendingOpen()
    var urls: [URL] = []
    private init() {}
}

extension Notification.Name {
    static let pendingOpenChanged = Notification.Name("MDViewer.pendingOpenChanged")
}
