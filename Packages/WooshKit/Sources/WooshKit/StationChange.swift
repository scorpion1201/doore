import Foundation
import SwiftProtobuf

public enum StationChange: Sendable {
    public enum Kind: Sendable { case station, charger, parkspot }
    case add(mapID: String, number: String, pose: MapPose, kind: Kind)
    case delete(mapID: String, number: String)

    public var type: String {
        switch self {
        case .add: return Woosh_Map_Mark_Storage_Create.protoMessageName
        case .delete: return Woosh_Map_Mark_Storage_Delete.protoMessageName
        }
    }

    public func allows(_ snapshot: RobotSnapshot) -> Bool {
        guard snapshot.workMode == 1 && snapshot.controlMode == 1 else { return false }
        switch self {
        case .delete(let id, let number): return id == snapshot.mapID && !number.isEmpty
        case .add(let id, let number, let pose, _):
            return id == snapshot.mapID && id == snapshot.poseMapID && !number.isEmpty &&
                [pose.x, pose.y, pose.theta].allSatisfy { Float($0).isFinite }
        }
    }

    public var body: Data {
        get throws {
            switch self {
            case .delete(_, let number):
                return try Woosh_Map_Mark_Storage_Delete.with { $0.no = number }.jsonUTF8Data()
            case .add(_, let number, let pose, let kind):
                return try Woosh_Map_Mark_Storage_Create.with { request in
                    request.storage.identity.no = number
                    request.storage.pose.real = .with { $0.x = Float(pose.x); $0.y = Float(pose.y); $0.theta = Float(pose.theta) }
                    switch kind {
                    case .station: break
                    case .charger: request.storage.charger = .init()
                    case .parkspot: request.storage.parkspot = .init()
                    }
                }.jsonUTF8Data()
            }
        }
    }
}
