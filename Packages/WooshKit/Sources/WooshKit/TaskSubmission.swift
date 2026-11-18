import Foundation
import SwiftProtobuf

public struct StationTask: Sendable {
    public let station: String
    public let kind: Int
    public let direction: Int
    public let group: Int32
    public let wait: Int32
    public let custom: Data
    public let source: Woosh_Task_WooshTask?

    public init(station: String, kind: Int, direction: Int, group: Int32, wait: Int32, custom: String) {
        self.station = station
        self.kind = kind
        self.direction = direction
        self.group = group
        self.wait = wait
        self.custom = Data(custom.utf8)
        self.source = nil
    }

    public init(copying task: Woosh_Task_WooshTask, station: String, kind: Int, direction: Int,
                group: Int32, wait: Int32, custom: Data) {
        self.station = station
        self.kind = kind
        self.direction = direction
        self.group = group
        self.wait = wait
        self.custom = custom
        self.source = task
    }
}

public struct TaskSubmission: Sendable {
    public enum Destination: Sendable, Equatable { case single, taskSet, predefined }
    private let sceneName: String
    private let mapID: String
    private let tasks: [StationTask]
    private let destination: Destination
    private let name: String
    private let repeats: Int32
    private let source: PredefinedSet?

    public init?(scene: SceneModel, mapID: String, tasks: [StationTask], destination: Destination,
                 name: String = "", repeats: Int32 = 0, source: PredefinedSet? = nil) {
        guard source.map({ scene.predefinedSets.contains($0) }) ?? true else { return nil }
        let sourceIDs = tasks.compactMap { $0.source?.base.id }
        guard Set(sourceIDs).count == sourceIDs.count,
              tasks.count <= Int(Int32.max), let map = scene.map(id: mapID), !tasks.isEmpty,
              repeats >= -1, (destination != .single || tasks.count == 1),
              destination == .single || !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              destination != .taskSet || repeats == 0,
              destination != .predefined || !scene.predefinedSets.contains(where: { $0.name == name }),
              tasks.allSatisfy({ task in
                  ((1...2).contains(task.direction) || (task.direction == 0 && task.source?.base.direction.rawValue == 0)) &&
                      (task.source.map { source?.content.tasks.contains($0) == true } ?? true) && task.wait >= -1 &&
                      UInt32(exactly: task.group) != nil &&
                      scene.referencedGroups[task.kind]?.contains(task.group) == true &&
                      map.stations.contains { $0.number == task.station }
              }) else { return nil }
        self.sceneName = scene.name
        self.mapID = mapID
        self.tasks = tasks
        self.destination = destination
        self.name = name
        self.repeats = repeats
        self.source = source
    }

    public func allows(_ snapshot: RobotSnapshot) -> Bool {
        snapshot.controlMode == 1 && snapshot.workMode == 2 && snapshot.state == 2 &&
            snapshot.mapID == mapID && snapshot.sceneName == sceneName && snapshot.emergencyStopped == false
    }

    public var type: String {
        switch destination {
        case .single: return Woosh_Robot_ExecTask.protoMessageName
        case .taskSet: return Woosh_Task_AddTask.protoMessageName
        case .predefined: return Woosh_Task_RepeatTask.protoMessageName
        }
    }

    public var body: Data {
        get throws {
            var options = JSONEncodingOptions()
            options.alwaysPrintEnumsAsInts = true
            if destination == .single {
                let input = tasks[0]
                guard let group = UInt32(exactly: input.group) else { throw SessionError.modeMismatch }
                let task = Woosh_Robot_ExecTask.with {
                    $0.markNo = input.station
                    $0.type = Woosh_Task_Type(rawValue: input.kind)!
                    $0.direction = Woosh_Task_Direction(rawValue: input.direction)!
                    $0.taskTypeNo = group
                    $0.custom = input.custom
                }
                return try task.jsonUTF8Data(options: options)
            }

            // The robot assigns the set identity. Never send a source preset's ID for a new set.
            var set = source?.content ?? Woosh_Task_WooshTaskSet()
            set.base.id = 0
            set.base.name = name
            set.clearExec()
            set.clearTime()
            if source == nil { set.custom.autoComplete = true }
            var usedIDs = Set(tasks.compactMap { $0.source?.base.id })
            var nextID: Int64 = 1
            set.tasks = try tasks.map { input in
                var task = input.source ?? Woosh_Task_WooshTask()
                task.clearExec()
                if input.source == nil {
                    while let candidate = Int32(exactly: nextID), usedIDs.contains(candidate) { nextID += 1 }
                    guard let freeID = Int32(exactly: nextID) else { throw SessionError.modeMismatch }
                    task.base.id = freeID
                    usedIDs.insert(freeID)
                    task.base.name = input.station
                    task.custom.executable = true
                }
                task.base.markNo = input.station
                task.base.type = Woosh_Task_Type(rawValue: input.kind)!
                task.base.direction = Woosh_Task_Direction(rawValue: input.direction)!
                task.base.typeNo = input.group
                task.base.waitTime = input.wait
                task.base.custom = input.custom
                return task
            }
            if destination == .taskSet {
                return try Woosh_Task_AddTask.with { $0.tset = set }.jsonUTF8Data(options: options)
            }
            return try Woosh_Task_RepeatTask.with {
                $0.order = .kPut
                $0.times = repeats
                $0.taskSet = set
            }.jsonUTF8Data(options: options)
        }
    }
}
