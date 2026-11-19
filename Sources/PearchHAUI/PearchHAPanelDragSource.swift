import AppKit
import SwiftUI

/// A small AppKit source view for panel reordering.
///
/// SwiftUI's macOS 13 `onDrag` API does not expose a drag-session completion
/// callback. This source owns the native session instead, so cancellation and
/// drops outside the panel always reach `onEnd`.
@MainActor
public struct PearchHAPanelDrag {
    public static let typeIdentifier = "dev.pearchha.panel-selection"

    public let payload: String
    public let title: String
    let onBegin: () -> Void
    let onEnd: (NSDragOperation) -> Void

    public init(
        payload: String,
        title: String,
        onBegin: @escaping () -> Void,
        onEnd: @escaping (NSDragOperation) -> Void
    ) {
        self.payload = payload
        self.title = title
        self.onBegin = onBegin
        self.onEnd = onEnd
    }
}

@MainActor
struct PearchHAPanelDragSource: NSViewRepresentable {
    let configuration: PearchHAPanelDrag

    func makeNSView(context: Context) -> PearchHAPanelDragSourceView {
        PearchHAPanelDragSourceView(
            payload: configuration.payload,
            title: configuration.title,
            onBegin: configuration.onBegin,
            onEnd: configuration.onEnd
        )
    }

    func updateNSView(_ nsView: PearchHAPanelDragSourceView, context: Context) {
        nsView.payload = configuration.payload
        nsView.title = configuration.title
        nsView.onBegin = configuration.onBegin
        nsView.onEnd = configuration.onEnd
    }
}

@MainActor
final class PearchHAPanelDragSourceView: NSView, NSDraggingSource {
    var payload: String
    var title: String
    var onBegin: () -> Void
    var onEnd: (NSDragOperation) -> Void

    private var mouseDownEvent: NSEvent?
    private var isDragging = false

    init(
        payload: String,
        title: String,
        onBegin: @escaping () -> Void,
        onEnd: @escaping (NSDragOperation) -> Void
    ) {
        self.payload = payload
        self.title = title
        self.onBegin = onBegin
        self.onEnd = onEnd
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        setAccessibilityElement(false)
        focusRingType = .none
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isOpaque: Bool { false }

    override func mouseDown(with event: NSEvent) {
        guard event.type == .leftMouseDown else {
            return
        }
        mouseDownEvent = event
        isDragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard !isDragging,
              let mouseDownEvent,
              window != nil,
              hypot(event.locationInWindow.x - mouseDownEvent.locationInWindow.x,
                    event.locationInWindow.y - mouseDownEvent.locationInWindow.y) >= 4
        else {
            return
        }

        isDragging = true
        self.mouseDownEvent = nil
        onBegin()

        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString(payload, forType: NSPasteboard.PasteboardType(PearchHAPanelDrag.typeIdentifier))
        let draggingItem = NSDraggingItem(pasteboardWriter: pasteboardItem)
        let preview = dragPreview
        draggingItem.setDraggingFrame(NSRect(origin: bounds.origin, size: preview.size), contents: preview)
        beginDraggingSession(with: [draggingItem], event: mouseDownEvent, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        mouseDownEvent = nil
        if !isDragging {
            super.mouseUp(with: event)
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        // The overlay is only installed over the identity/header region. Still
        // forward context-menu clicks so the existing SwiftUI menu remains the
        // owner of secondary-button behavior.
        nextResponder?.rightMouseDown(with: event)
    }

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        context == .withinApplication ? .move : []
    }

    func draggingSession(
        _ session: NSDraggingSession,
        endedAt screenPoint: NSPoint,
        operation: NSDragOperation
    ) {
        isDragging = false
        mouseDownEvent = nil
        onEnd(operation)
    }

    private var dragPreview: NSImage {
        let text = title.isEmpty ? (payload.split(separator: ":", maxSplits: 1).last.map(String.init) ?? payload) : title
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.labelColor
        ]
        let textSize = (text as NSString).size(withAttributes: attributes)
        let image = NSImage(size: NSSize(width: min(max(textSize.width + 16, 48), 180), height: 24))
        image.lockFocus()
        NSColor.windowBackgroundColor.withAlphaComponent(0.92).setFill()
        NSBezierPath(roundedRect: NSRect(origin: .zero, size: image.size), xRadius: 6, yRadius: 6).fill()
        (text as NSString).draw(
            in: NSRect(x: 8, y: (image.size.height - textSize.height) / 2, width: image.size.width - 16, height: textSize.height),
            withAttributes: attributes
        )
        image.unlockFocus()
        return image
    }
}
