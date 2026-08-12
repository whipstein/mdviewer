//
//  FilePicker.swift
//  MDViewer
//
//  Created by Matt Braunstein on 7/12/26.
//

import AppKit

enum FilePicker {
    static func pickMarkdownURL() -> URL? {
        let panel = NSOpenPanel()
        // No content-type restriction: allow selecting any file (read as UTF-8 text).
        panel.allowsOtherFileTypes = true
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        return panel.runModal() == .OK ? panel.url : nil
    }
}

