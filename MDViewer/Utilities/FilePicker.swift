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
        panel.allowedContentTypes = [.markdown, .plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        return panel.runModal() == .OK ? panel.url : nil
    }
}

