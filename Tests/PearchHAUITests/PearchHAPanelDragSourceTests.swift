#if canImport(XCTest)
import AppKit
import SwiftUI
import XCTest
@testable import PearchHAUI

@MainActor
final class PearchHAPanelDragSourceTests: XCTestCase {
    func testPanelDragSourceCreatesNonAccessibleOverlay() throws {
        let root = PearchHAPanelDragSource(
            configuration: PearchHAPanelDrag(
                payload: "entity:switch.office_lamp",
                title: "Office lamp",
                onBegin: {},
                onEnd: { _ in }
            )
        )
        let hostingView = NSHostingView(rootView: root.frame(width: 120, height: 24))
        hostingView.frame = NSRect(x: 0, y: 0, width: 120, height: 24)
        hostingView.layoutSubtreeIfNeeded()

        let sourceView = try XCTUnwrap(descendant(of: hostingView) { $0 is PearchHAPanelDragSourceView }) as! PearchHAPanelDragSourceView
        XCTAssertFalse(sourceView.isAccessibilityElement())
    }

    func testPanelDragSourceClickDoesNotBeginReorder() throws {
        var beginCount = 0
        var endCount = 0
        let (sourceView, window) = makeSourceView(
            onBegin: { beginCount += 1 },
            onEnd: { _ in endCount += 1 }
        )
        let down = try XCTUnwrap(mouseEvent(type: .leftMouseDown, x: 12, window: window))
        let up = try XCTUnwrap(mouseEvent(type: .leftMouseUp, x: 12, window: window))

        sourceView.mouseDown(with: down)
        sourceView.mouseUp(with: up)

        XCTAssertEqual(beginCount, 0)
        XCTAssertEqual(endCount, 0)
    }

    func testPanelDragSourceSubthresholdMovementDoesNotBeginReorder() throws {
        var beginCount = 0
        var endCount = 0
        let (sourceView, window) = makeSourceView(
            onBegin: { beginCount += 1 },
            onEnd: { _ in endCount += 1 }
        )
        let down = try XCTUnwrap(mouseEvent(type: .leftMouseDown, x: 12, window: window))
        let dragged = try XCTUnwrap(mouseEvent(type: .leftMouseDragged, x: 15, window: window))
        let up = try XCTUnwrap(mouseEvent(type: .leftMouseUp, x: 15, window: window))

        sourceView.mouseDown(with: down)
        sourceView.mouseDragged(with: dragged)
        sourceView.mouseUp(with: up)

        XCTAssertEqual(beginCount, 0)
        XCTAssertEqual(endCount, 0)
    }

    func testPanelDragSourceMovementAfterMouseUpDoesNotBeginReorder() throws {
        var beginCount = 0
        var endCount = 0
        let (sourceView, window) = makeSourceView(
            onBegin: { beginCount += 1 },
            onEnd: { _ in endCount += 1 }
        )
        let down = try XCTUnwrap(mouseEvent(type: .leftMouseDown, x: 12, window: window))
        let up = try XCTUnwrap(mouseEvent(type: .leftMouseUp, x: 12, window: window))
        let dragged = try XCTUnwrap(mouseEvent(type: .leftMouseDragged, x: 24, window: window))

        sourceView.mouseDown(with: down)
        sourceView.mouseUp(with: up)
        sourceView.mouseDragged(with: dragged)

        XCTAssertEqual(beginCount, 0)
        XCTAssertEqual(endCount, 0)
    }

    private func descendant(of view: NSView, matching predicate: (NSView) -> Bool) -> NSView? {
        if predicate(view) {
            return view
        }
        for child in view.subviews {
            if let match = descendant(of: child, matching: predicate) {
                return match
            }
        }
        return nil
    }

    private func makeSourceView(
        onBegin: @escaping () -> Void,
        onEnd: @escaping (NSDragOperation) -> Void
    ) -> (PearchHAPanelDragSourceView, NSWindow) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 120, height: 24),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        let sourceView = PearchHAPanelDragSourceView(
            payload: "entity:switch.office_lamp",
            title: "Office lamp",
            onBegin: onBegin,
            onEnd: onEnd
        )
        sourceView.frame = NSRect(x: 0, y: 0, width: 120, height: 24)
        window.contentView = sourceView
        window.layoutIfNeeded()
        return (sourceView, window)
    }

    private func mouseEvent(
        type: NSEvent.EventType,
        x: CGFloat,
        window: NSWindow
    ) -> NSEvent? {
        NSEvent.mouseEvent(
            with: type,
            location: NSPoint(x: x, y: 12),
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 1,
            clickCount: 1,
            pressure: 1
        )
    }
}
#endif
