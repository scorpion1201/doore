import Foundation

/// An app-owned, editable copy. These types are never serialized as robot messages.
public struct DraftPoint: Equatable, Codable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    func distance(to other: Self) -> Double { hypot(x - other.x, y - other.y) }
}

public struct DraftItem: Identifiable, Equatable, Codable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case point, field, guide, paint
    }

    public let id: UUID
    public let kind: Kind
    public var subtype: String
    public var points: [DraftPoint]
    public var number: String
    public var description: String
    public var heading: Double
    public var arrival: String?
    public var dockingChecks: Set<String>?
    public var speedLimit: Double?
    public var capacity: UInt32?
    public var width: Double?
    public var allowsAvoidance: Bool?

    public init(id: UUID = UUID(), kind: Kind, subtype: String, points: [DraftPoint],
                number: String = "", description: String = "", heading: Double = 0,
                arrival: String? = nil, dockingChecks: Set<String>? = nil) {
        self.id = id
        self.kind = kind
        self.subtype = subtype
        self.points = points
        self.number = number
        self.description = description
        self.heading = heading
        self.arrival = arrival
        self.dockingChecks = dockingChecks
    }

    public func distance(to point: DraftPoint) -> Double {
        guard let first = points.first else { return .infinity }
        var distance = first.distance(to: point)
        var vertices = points
        if kind == .field { vertices.append(first) }
        for (start, end) in zip(vertices, vertices.dropFirst()) {
            let dx = end.x - start.x, dy = end.y - start.y
            let lengthSquared = dx * dx + dy * dy
            guard lengthSquared > 0 else { continue }
            let projection = ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared
            let fraction = min(1, max(0, projection))
            let closest = DraftPoint(x: start.x + fraction * dx, y: start.y + fraction * dy)
            distance = min(distance, closest.distance(to: point))
        }
        return distance
    }
}

public struct SceneDraft: Sendable {
    /// Undo history is transient. The original baseline stays in the saved copy for change counts.
    public struct Snapshot: Codable, Sendable, Equatable {
        public let original: [DraftItem]
        public let items: [DraftItem]
        public let originalSets: [DraftTaskSet]
        public let taskSets: [DraftTaskSet]
    }

    public private(set) var items: [DraftItem]
    private let original: [DraftItem]
    public private(set) var taskSets: [DraftTaskSet]
    private let originalSets: [DraftTaskSet]
    private typealias Revision = (items: [DraftItem], taskSets: [DraftTaskSet])
    private var past: [Revision] = []
    private var future: [Revision] = []

    public init(original: [DraftItem] = [], taskSets: [DraftTaskSet] = []) {
        self.originalSets = taskSets
        self.taskSets = taskSets
        self.original = original
        self.items = original
    }

    public init(snapshot: Snapshot) {
        original = snapshot.original
        items = snapshot.items
        originalSets = snapshot.originalSets
        taskSets = snapshot.taskSets
    }

    public var snapshot: Snapshot { Snapshot(original: original, items: items, originalSets: originalSets, taskSets: taskSets) }
    public var canUndo: Bool { !past.isEmpty }
    public var canRedo: Bool { !future.isEmpty }

    public var changedItemCount: Int {
        changes(original, items) + changes(originalSets, taskSets)
    }

    private func changes<T: Identifiable & Equatable>(_ original: [T], _ items: [T]) -> Int {
        var baseline = [T.ID: T]()
        for item in original { baseline[item.id] = item }
        var count = 0
        for item in items {
            if baseline.removeValue(forKey: item.id) != item { count += 1 }
        }
        return count + baseline.count
    }

    public mutating func put(_ item: DraftItem) {
        guard !item.points.isEmpty, item.heading.isFinite,
              item.points.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { return }
        var next = items
        if let index = next.firstIndex(where: { $0.id == item.id }) {
            next[index] = item
        } else {
            next.append(item)
        }
        record(next)
    }

    public mutating func move(_ id: UUID, dx: Double, dy: Double) {
        guard var item = items.first(where: { $0.id == id }) else { return }
        item.points = item.points.map { DraftPoint(x: $0.x + dx, y: $0.y + dy) }
        put(item)
    }

    public mutating func delete(_ id: UUID) {
        record(items.filter { $0.id != id })
    }

    public mutating func undo() {
        guard let previous = past.popLast() else { return }
        future.append((items, taskSets))
        (items, taskSets) = previous
    }

    public mutating func redo() {
        guard let next = future.popLast() else { return }
        past.append((items, taskSets))
        (items, taskSets) = next
    }

    public mutating func put(_ taskSet: DraftTaskSet) {
        var next = taskSets
        if let index = next.firstIndex(where: { $0.id == taskSet.id }) { next[index] = taskSet }
        else { next.append(taskSet) }
        record(items, sets: next)
    }

    public mutating func deleteTaskSet(_ id: UUID) {
        record(items, sets: taskSets.filter { $0.id != id })
    }

    private mutating func record(_ next: [DraftItem], sets: [DraftTaskSet]? = nil) {
        let nextSets = sets ?? taskSets
        guard next != items || nextSets != taskSets else { return }
        past.append((items, taskSets))
        taskSets = nextSets
        items = next
        future.removeAll()
    }
}
