import Foundation
import SwiftProtobuf

/// The full generated message is retained when the form changes a single field.
public struct DraftTaskSet: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var content: Woosh_Task_WooshTaskSet
    public var repeatInfo: Woosh_Task_RepeatTask?
    public var callInfo: Woosh_Task_CallTask?

    public init(repeating message: Woosh_Task_RepeatTask) {
        id = UUID()
        content = message.taskSet
        var metadata = message
        metadata.clearTaskSet()
        repeatInfo = metadata
    }

    public init(call message: Woosh_Task_CallTask) {
        id = UUID()
        content = message.taskSet
        var metadata = message
        metadata.clearTaskSet()
        callInfo = metadata
    }

    private enum Keys: String, CodingKey { case id, content, repeatInfo, callInfo }

    public init(from decoder: Swift.Decoder) throws {
        let fields = try decoder.container(keyedBy: Keys.self)
        id = try fields.decode(UUID.self, forKey: .id)
        content = try Woosh_Task_WooshTaskSet(serializedBytes: fields.decode(Data.self, forKey: .content))
        repeatInfo = try fields.decodeIfPresent(Data.self, forKey: .repeatInfo).map { try Woosh_Task_RepeatTask(serializedBytes: $0) }
        callInfo = try fields.decodeIfPresent(Data.self, forKey: .callInfo).map { try Woosh_Task_CallTask(serializedBytes: $0) }
    }

    public func encode(to encoder: Swift.Encoder) throws {
        var fields = encoder.container(keyedBy: Keys.self)
        try fields.encode(id, forKey: .id)
        try fields.encode(content.serializedData(), forKey: .content)
        try fields.encodeIfPresent(repeatInfo?.serializedData(), forKey: .repeatInfo)
        try fields.encodeIfPresent(callInfo?.serializedData(), forKey: .callInfo)
    }
}

public struct SceneEditingDetails: Sendable {
    public let taskSets: [DraftTaskSet]
    public let actionGroup: String
    public let geometry: [DraftItem]
    private let storages: [Woosh_Map_Mark_Storage]

    public init(sceneData: Data, mapID: String) throws {
        var options = JSONDecodingOptions()
        options.ignoreUnknownFields = true
        let source = try Woosh_Map_SceneData(jsonUTF8Data: sceneData, options: options)
        taskSets = source.taskInfo.repeatTasks.map(DraftTaskSet.init(repeating:)) + source.taskInfo.callTasks.map(DraftTaskSet.init(call:))
        actionGroup = source.actionGroup
        let map = source.maps.first { String($0.id) == mapID }
        storages = map?.markInfo.storages ?? []
        geometry = map.map(Self.geometry) ?? []
    }

    private static func geometry(_ map: Woosh_Map_SceneData.Map) -> [DraftItem] {
        let fields = map.fieldInfo
        let grouped: [(String, [Woosh_Map_Field_NavField])] = [
            ("양방향", fields.bidirectionWays.map(\.navFiled)), ("단일 차로", fields.singleWays.map(\.navFiled)),
            ("일방통행", fields.oneWays.map(\.navFiled)), ("교차로", fields.crossings.map(\.navFiled)),
            ("협로", fields.narrowPassages.map(\.navFiled)), ("위치 보정", fields.locateFields.map(\.navFiled)),
            ("경사", fields.rampFields.map(\.navFiled)), ("주행거리계", fields.odomFields.map(\.navFiled)),
            ("자동문", fields.autodoorFields.map(\.navFiled)), ("속도 제한", fields.speedLimitFields.map(\.navFiled)),
            ("소방", fields.fireFields.map(\.navFiled)), ("경고", fields.warnFields.map(\.navFiled)),
            ("유도", fields.guideFields.map(\.navFiled))
        ]
        func points(_ source: [Woosh_Common_Point]) -> [DraftPoint] {
            source.map { DraftPoint(x: Double($0.x), y: Double($0.y)) }
        }
        var result = [DraftItem]()
        for (type, regions) in grouped {
            for region in regions where region.vertexs.count >= 3 {
                var item = DraftItem(kind: .field, subtype: type, points: points(region.vertexs), number: String(region.id))
                item.speedLimit = Double(region.maxSpeed)
                item.capacity = region.capacity
                result.append(item)
            }
        }
        func appendGuide(_ type: String, _ path: [Woosh_Common_Point], _ width: Float, _ avoids: Bool) {
            guard path.count >= 2 else { return }
            var item = DraftItem(kind: .guide, subtype: type, points: points(path))
            item.width = Double(width)
            item.allowsAvoidance = avoids
            result.append(item)
        }
        for path in map.pathInfo.monoPaths { appendGuide("단방향 경로", path.path, path.width, path.allowAvoid) }
        for path in map.pathInfo.bidirectPaths { appendGuide("양방향 경로", path.path, path.width, path.allowAvoid) }
        return result
    }

    public func stationProperties(number: String) -> (arrival: String?, dockingChecks: Set<String>?) {
        guard let storage = storages.first(where: { $0.identity.no == number }) else { return (nil, nil) }
        let arrival: String?
        switch storage.nav.arr {
        case .kVague: arrival = "대략 도착"
        case .kAccurate: arrival = "정밀 도착"
        default: arrival = nil
        }
        let verify = storage.dock.verify
        var checks = Set<String>()
        if verify.topPhotoelec { checks.insert("광전 센서") }
        if verify.bottomMagnetic { checks.insert("자기 테이프") }
        if verify.backFeature { checks.insert("라이다 특징") }
        return (arrival, storage.dock.hasVerify ? checks : nil)
    }
}
