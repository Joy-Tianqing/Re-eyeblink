import AppKit

enum MenuBarIcon {
    static let active = makeImage(isPaused: false)
    static let paused = makeImage(isPaused: true)

    private static func makeImage(isPaused: Bool) -> NSImage {
        // Redraw the app icon's three strokes at menu-bar size for crisp Retina rendering.
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.setStroke()
            let face = NSBezierPath()
            face.lineWidth = 1.9
            face.lineCapStyle = .round
            face.lineJoinStyle = .round

            face.move(to: NSPoint(x: 3.4, y: 10.8))
            face.line(to: NSPoint(x: 3.4, y: 14.1))

            face.move(to: NSPoint(x: 10.1, y: 12.1))
            face.curve(to: NSPoint(x: 15.4, y: 12.1),
                       controlPoint1: NSPoint(x: 11.8, y: 13.2),
                       controlPoint2: NSPoint(x: 13.7, y: 13.2))

            face.move(to: NSPoint(x: 3.5, y: 7.1))
            face.curve(to: NSPoint(x: 13.5, y: 7.1),
                       controlPoint1: NSPoint(x: 6.5, y: 3.9),
                       controlPoint2: NSPoint(x: 10.3, y: 3.9))
            face.stroke()

            if isPaused {
                let slash = NSBezierPath()
                slash.lineCapStyle = .round
                slash.move(to: NSPoint(x: 2.2, y: 16))
                slash.line(to: NSPoint(x: 15.8, y: 2.4))
                // Clear a small gap so the pause slash stays distinct from the face.
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current?.compositingOperation = .copy
                NSColor.clear.setStroke()
                slash.lineWidth = 3.5
                slash.stroke()
                NSGraphicsContext.restoreGraphicsState()
                NSColor.black.setStroke()
                slash.lineWidth = 1.5
                slash.stroke()
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}
