import AppKit
import SwiftUI

/// Native tracking remains active while the chart is in a grouped macOS Form.
/// Only this view's visible rectangle is tracked; no global input monitor is used.
struct ChartPointerSurface: NSViewRepresentable {
    var onMove: (CGPoint?) -> Void
    func makeNSView(context: Context) -> PointerView { PointerView() }
    func updateNSView(_ view: PointerView, context: Context) { view.onMove = onMove }

    final class PointerView: NSView {
        var onMove: ((CGPoint?) -> Void)?
        private var tracking: NSTrackingArea?
        override var isFlipped: Bool { true }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.acceptsMouseMovedEvents = true
        }
        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let tracking { removeTrackingArea(tracking) }
            let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
            addTrackingArea(area); tracking = area
        }
        override func mouseEntered(with event: NSEvent) { publish(event) }
        override func mouseMoved(with event: NSEvent) { publish(event) }
        override func mouseDragged(with event: NSEvent) { publish(event) }
        override func mouseDown(with event: NSEvent) { publish(event) }
        override func mouseExited(with event: NSEvent) { onMove?(nil) }
        private func publish(_ event: NSEvent) { onMove?(convert(event.locationInWindow, from: nil)) }
    }
}
