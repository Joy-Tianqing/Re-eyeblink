import Foundation
import CoreGraphics

public enum FaceTargetStatus: String, Sendable { case none, acquiring, tracking, lost, ambiguous }

/// Spatial continuity only, not identity recognition. Indices refer to this
/// frame's input array and must never be used as persistent person identifiers.
public struct FaceTargetSelection: Equatable, Sendable {
    public var status: FaceTargetStatus
    public var visibleFaceCount: Int
    public var selectedIndex: Int?
    public var revision: UInt64
}

/// A bounded, geometry-only target lock for the ordered camera queue. A new
/// bystander cannot replace a missing target elsewhere in the image.
public struct FaceTargetTracker: Sendable {
    private var anchor: CGRect?
    private var previousTime: TimeInterval?
    private var pending: CGRect?
    private var pendingSince: TimeInterval?
    private var confirming = true
    private var brokeContinuity = false
    private var revision: UInt64 = 0
    public init() {}
    public mutating func reset() {
        let next = revision &+ 1
        self = .init(); revision = next
    }
    /// A new camera lease reconfirms the same spatial anchor without inheriting
    /// a half-completed acquisition. No pixel/appearance data is retained.
    public mutating func beginLease() {
        previousTime = nil; pending = nil; pendingSince = nil; confirming = true
    }
    public mutating func select(_ boxes: [CGRect], at time: TimeInterval) -> FaceTargetSelection {
        func result(_ status: FaceTargetStatus, _ index: Int? = nil) -> FaceTargetSelection {
            .init(status: status, visibleFaceCount: boxes.count, selectedIndex: index, revision: revision)
        }
        guard time.isFinite, previousTime.map({ time > $0 }) ?? true else {
            interrupt(); return result(anchor == nil ? .none : .lost)
        }
        if let previousTime, time - previousTime > 0.2 { interrupt() }
        previousTime = time
        let valid = boxes.indices.filter { Self.usable(boxes[$0]) }
        let selected: Int
        if let anchor {
            let matches = valid.compactMap { index -> (Int, Double)? in
                let box = boxes[index], ratio = Self.area(box) / Self.area(anchor)
                let shift = Self.distance(box, anchor)
                let overlap = Self.iou(box, anchor)
                guard (0.6...1.65).contains(ratio), shift <= 0.35, overlap >= 0.3 else { return nil }
                return (index, shift + abs(log(ratio))*0.35 + (1-overlap)*0.5)
            }.sorted { $0.1 < $1.1 }
            guard let best = matches.first else { interrupt(); return result(.lost) }
            guard matches.count == 1 || matches[1].1 - best.1 >= 0.25 else {
                interrupt(); return result(.ambiguous)
            }
            selected = best.0
        } else {
            guard !valid.isEmpty else { interrupt(); return result(.none) }
            let ranked = valid.sorted { Self.area(boxes[$0]) > Self.area(boxes[$1]) }
            guard ranked.count == 1 || Self.area(boxes[ranked[0]]) >= Self.area(boxes[ranked[1]])*2.25 else {
                interrupt(); return result(.ambiguous)
            }
            selected = ranked[0]
        }
        let box = boxes[selected]
        if confirming {
            if let pending, Self.distance(box, pending) > 0.2 || Self.iou(box, pending) < 0.5 {
                self.pending = box; pendingSince = time
            }
            // Keep the window's first box as the reference. Updating it every
            // frame lets small adjacent steps accumulate into an unstable lock.
            if pending == nil { pending = box; pendingSince = time }
            guard time - pendingSince! >= 0.3 else { return result(.acquiring, selected) }
            if revision == 0 || brokeContinuity { revision &+= 1 }
            confirming = false; brokeContinuity = false; pending = nil; pendingSince = nil
        }
        anchor = box
        return result(.tracking, selected)
    }
    private mutating func interrupt() {
        confirming = true; pending = nil; pendingSince = nil
        if anchor != nil { brokeContinuity = true }
    }
    private static func usable(_ box: CGRect) -> Bool {
        [box.minX,box.minY,box.width,box.height].allSatisfy(\.isFinite) && box.width >= 0.04 && box.height >= 0.04 &&
            box.minX >= 0 && box.minY >= 0 && box.maxX <= 1 && box.maxY <= 1
    }
    private static func area(_ box: CGRect) -> Double { box.width*box.height }
    private static func distance(_ a: CGRect, _ b: CGRect) -> Double {
        hypot(a.midX-b.midX, a.midY-b.midY) / sqrt(area(b))
    }
    private static func iou(_ a: CGRect, _ b: CGRect) -> Double {
        let intersection = a.intersection(b)
        let overlap = intersection.isNull ? 0 : area(intersection)
        return overlap / (area(a)+area(b)-overlap)
    }
}
