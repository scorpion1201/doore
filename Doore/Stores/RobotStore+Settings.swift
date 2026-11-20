import WooshKit

extension RobotStore {
    func setting(_ change: RobotSettingChange) async {
        _ = await perform(.changeSetting(change))
    }
}

extension RobotStore {
    func addStation(mapID: String, number: String, kind: StationChange.Kind) async {
        guard let map = activeMap, map.id == mapID, !map.stations.contains(where: { $0.number == number }),
              let pose, poseMapID == mapID else { return }
        _ = await perform(.station(.add(mapID: map.id, number: number, pose: pose, kind: kind)))
    }

    func deleteStation(mapID: String, number: String) async {
        guard let map = activeMap, map.id == mapID, map.stations.contains(where: { $0.number == number }) else { return }
        _ = await perform(.station(.delete(mapID: map.id, number: number)))
    }
}
