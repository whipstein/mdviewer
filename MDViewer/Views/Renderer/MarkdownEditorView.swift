import AppKit
import SwiftUI

/// Plain-text Markdown editor backed by NSTextView. Clicking in the preview posts a
/// source line through `renderVM`, and this view scrolls to and selects that line.
struct MarkdownEditorView: NSViewRepresentable {
    @ObservedObject var documentVM: DocumentViewModel
    @ObservedObject var renderVM: RenderViewModel

    func makeCoordinator() -> Coordinator {
        Coordinator(documentVM: documentVM)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }

        textView.delegate = context.coordinator
        textView.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.allowsUndo = true
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.string = documentVM.text

        context.coordinator.textView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }

        // Sync when the file is reloaded externally (e.g., FileWatcher) and the
        // user has no unsaved edits that would be clobbered.
        if !documentVM.isDirty, textView.string != documentVM.text {
            textView.string = documentVM.text
        }

        // Apply a click-to-locate request coming from the preview.
        if let request = renderVM.editorScrollRequest,
           request.id != context.coordinator.lastHandledRequestID {
            context.coordinator.lastHandledRequestID = request.id
            context.coordinator.moveToLine(request.line)
        }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate {
        let documentVM: DocumentViewModel
        weak var textView: NSTextView?
        var lastHandledRequestID: Int = 0

        init(documentVM: DocumentViewModel) {
            self.documentVM = documentVM
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            documentVM.updateText(textView.string)
        }

        /// Scroll the given source line to the top of the viewport, place the caret
        /// there, and focus the editor.
        func moveToLine(_ line: Int) {
            guard let textView,
                  let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else { return }

            let text = textView.string as NSString
            let range = Self.characterRange(forLine: line, in: text)

            textView.setSelectedRange(NSRange(location: range.location, length: 0))
            textView.window?.makeFirstResponder(textView)

            let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            var lineRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            lineRect.origin.y += textView.textContainerInset.height

            guard let clipView = textView.enclosingScrollView?.contentView else { return }
            let maxY = max(0, textView.bounds.height - clipView.bounds.height)
            let targetY = min(max(0, lineRect.minY), maxY)
            clipView.scroll(to: NSPoint(x: 0, y: targetY))
            textView.enclosingScrollView?.reflectScrolledClipView(clipView)
        }

        /// Character range of the given 0-based line (excluding its trailing newline).
        static func characterRange(forLine line: Int, in text: NSString) -> NSRange {
            guard text.length > 0 else { return NSRange(location: 0, length: 0) }

            var index = 0
            var currentLine = 0
            while currentLine < line {
                let newline = text.range(of: "\n", options: [], range: NSRange(location: index, length: text.length - index))
                if newline.location == NSNotFound {
                    return NSRange(location: text.length, length: 0)
                }
                index = newline.location + 1
                currentLine += 1
            }

            let rest = NSRange(location: index, length: text.length - index)
            let lineEnd = text.range(of: "\n", options: [], range: rest)
            let end = lineEnd.location == NSNotFound ? text.length : lineEnd.location
            return NSRange(location: index, length: end - index)
        }
    }
}
