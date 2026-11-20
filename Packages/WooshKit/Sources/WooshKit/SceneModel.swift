import Foundation
import SwiftProtobuf

private func decodeSceneMessage<M: SwiftProtobuf.Message>(_ type: M.Type, from data: Data) throws -> M {
    var options = JSONDecodingOptions()
    options.ignoreUnknownFields = true
    return try M(jsonUTF8Data: data, options: options)
}

// A read-only projection of the documented SceneData and PoseSpeed JSON fields.
// The source message remains authoritative; this model must never be re-encoded for upload.
public struct MapPose: Equatable, Sendable {
    public let x: Double
    public let y: Double
    public let theta: Double

    public init(x: Double, y: Double, theta: Double = 0) {
        self.x = x
        self.y = y
        self.theta = theta
    }

    init?(_ pose: Woosh_Common_Pose2D) {
        guard pose.x.isFinite, pose.y.isFinite, pose.theta.isFinite else { return nil }
        self.init(x: Double(pose.x), y: Double(pose.y), theta: Double(pose.theta))
    }

    fileprivate init?(_ point: Woosh_Common_Point) {
        guard point.x.isFinite, point.y.isFinite else { return nil }
        self.init(x: Double(point.x), y: Double(point.y))
    }

    public init?(data: Data) {
        guard let message = try? decodeSceneMessage(Woosh_Robot_PoseSpeed.self, from: data),
              message.hasPose else { return nil }
        self.init(message.pose)
    }

    public static func path(data: Data) -> [MapPose] {
        guard let message = try? decodeSceneMessage(Woosh_Robot_NavPath.self, from: data) else { return [] }
        return message.path.poses.compactMap(MapPose.init)
    }
}

public struct Station: Equatable, Sendable {
    public let number: String
    public let pose: MapPose?
    public let description: String
    fileprivate let category: Woosh_Map_Mark_Storage.OneOf_Category?

    fileprivate init?(_ message: Woosh_Map_Mark_Storage) {
        guard !message.identity.no.isEmpty else { return nil }
        self.number = message.identity.no
        self.description = message.identity.desc
        self.pose = message.pose.hasReal ? MapPose(message.pose.real) : nil
        self.category = message.category
    }

    public var kind: String {
        switch category {
        case .rack: "선반"
        case .parkspot: "주차 자리"
        case .charger: "충전기"
        case .palletPlatform: "팔레트 대"
        case .liftTrolley: "리프트 카트"
        case .tractorTrailer: "견인 트레일러"
        case .rollerStation: "롤러 스테이션"
        case .armWorktop: "로봇 팔 작업대"
        case nil: "스테이션"
        }
    }

    fileprivate func accepts(_ kind: Woosh_Task_Type, robot: UInt32?) -> Bool {
        let robots: [UInt32]
        switch category {
        case .parkspot(let spot) where kind == .kParking: robots = spot.robots
        case .charger(let charger) where kind == .kCharge || (kind == .kParking && charger.parking): robots = charger.robots
        default: return false
        }
        return robots.isEmpty || robot.map(robots.contains) == true
    }
}

public struct MapModel: Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let floor: String?
    public let version: String?
    public let modified: String?
    public let resolution: Double?
    public let origin: MapPose?
    public let imageData: Data?
    public let noGoData: Data?
    public let trafficData: Data?
    public let stations: [Station]
    public let fields: [[MapPose]]
    public let guides: [[MapPose]]

    fileprivate init(_ map: Woosh_Map_SceneData.Map) {
        self.id = String(map.id)
        self.name = map.name
        self.floor = map.markInfo.floorName.isEmpty ? nil : map.markInfo.floorName
        self.version = map.hasMarkInfo ? String(map.markInfo.version) : nil
        self.modified = map.timeWrite.isEmpty ? nil : map.timeWrite
        self.resolution = map.resolution > 0 && map.resolution.isFinite ? Double(map.resolution) : nil
        self.origin = map.hasOrigin ? MapPose(map.origin) : nil
        self.imageData = map.mapPng.isEmpty ? nil : map.mapPng
        self.noGoData = map.keepoutPng.isEmpty ? nil : map.keepoutPng
        self.trafficData = map.trafficKeepoutPng.isEmpty ? nil : map.trafficKeepoutPng
        self.stations = map.markInfo.storages.compactMap(Station.init)
        let f = map.fieldInfo
        let fieldGroups = [
            f.bidirectionWays.map(\.navFiled),
            f.singleWays.map(\.navFiled),
            f.oneWays.map(\.navFiled),
            f.crossings.map(\.navFiled),
            f.narrowPassages.map(\.navFiled),
            f.locateFields.map(\.navFiled),
            f.rampFields.map(\.navFiled),
            f.odomFields.map(\.navFiled),
            f.autodoorFields.map(\.navFiled),
            f.speedLimitFields.map(\.navFiled),
            f.fireFields.map(\.navFiled),
            f.warnFields.map(\.navFiled),
            f.guideFields.map(\.navFiled)
        ]
        self.fields = fieldGroups.joined().map { $0.vertexs.compactMap(MapPose.init) }.filter { $0.count >= 3 }
        let paths = map.pathInfo.monoPaths.map(\.path) + map.pathInfo.bidirectPaths.map(\.path)
        self.guides = paths.map { $0.compactMap(MapPose.init) }.filter { $0.count > 1 }
    }

    public func pixel(for point: MapPose, height: Double) -> (x: Double, y: Double)? {
        guard let origin, let resolution else { return nil }
        return ((point.x - origin.x) / resolution, height - (point.y - origin.y) / resolution)
    }

    public func world(xPixel: Double, yPixel: Double, height: Double) -> MapPose? {
        guard let origin, let resolution else { return nil }
        return MapPose(x: origin.x + xPixel * resolution, y: origin.y + (height - yPixel) * resolution)
    }

    public func shortcut(for kind: Woosh_Task_Type, selected: String?, robotNumber: String?) -> StationShortcut? {
        let robot = robotNumber.flatMap(UInt32.init)
        let matches = stations.filter { $0.number == selected }
        guard matches.count <= 1 else { return nil }
        let picked = matches.first
        switch kind {
        case .kCharge:
            guard let picked, case .charger = picked.category else { return .charge(station: nil) }
            return picked.accepts(kind, robot: robot) ? .charge(station: picked.number) : nil
        case .kParking:
            if let picked, picked.accepts(kind, robot: robot) { return .park(station: picked.number) }
            let eligible = stations.filter { $0.accepts(kind, robot: robot) }
            guard eligible.count == 1, let spot = eligible.first,
                  stations.filter({ $0.number == spot.number }).count == 1 else { return nil }
            return .park(station: spot.number)
        default:
            return nil
        }
    }
}

public struct PredefinedSet: Identifiable, Equatable, Sendable {
    public let id: Int
    public let name: String
    public let content: Woosh_Task_WooshTaskSet
    public let repeatCount: Int32?
    public var taskCount: Int { content.tasks.count }
}

public struct SceneModel: Equatable, Sendable {
    public let predefinedSets: [PredefinedSet]
    /// The opaque action-group document has no recovered schema. Only combinations
    /// already referenced by a preset in this same scene can be offered for reuse.
    public let referencedGroups: [Int: Set<Int32>]
    public let name: String
    public let maps: [MapModel]

    public init(data: Data) throws {
        let scene = try decodeSceneMessage(Woosh_Map_SceneData.self, from: data)
        guard !scene.name.isEmpty else { throw CocoaError(.coderReadCorrupt) }
        self.name = scene.name
        let sources = scene.taskInfo.repeatTasks.map { ($0.taskSet, Optional($0.times)) }
            + scene.taskInfo.callTasks.map { ($0.taskSet, Int32?.none) }
        let sets = sources.map { $0.0 }
        let document = try? JSONSerialization.jsonObject(with: Data(scene.actionGroup.utf8))
        var groups: [Int: Set<Int32>] = [:]
        if (document as? [String: Any])?.isEmpty == false || (document as? [Any])?.isEmpty == false {
            for task in sets.flatMap(\.tasks) where task.hasBase && task.base.typeNo >= 0 && !task.base.markNo.isEmpty {
                guard (1...4).contains(task.base.type.rawValue) else { continue }
                groups[task.base.type.rawValue, default: []].insert(task.base.typeNo)
            }
        }
        referencedGroups = groups
        var seen = Set<Int>()
        predefinedSets = sources.compactMap { set, count in
            let id = Int(set.base.id)
            guard set.hasBase, !set.base.name.isEmpty, seen.insert(id).inserted else { return nil }
            return PredefinedSet(id: id, name: set.base.name, content: set, repeatCount: count)
        }
        maps = scene.maps.map(MapModel.init)
    }

    public func map(id: String?) -> MapModel? {
        guard let id else { return nil }
        return maps.first { $0.id == id }
    }
}
