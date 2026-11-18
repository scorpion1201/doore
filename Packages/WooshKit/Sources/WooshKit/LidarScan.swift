import Foundation
import SwiftProtobuf

/// Scan measurements in the reported sensor frame. ScannerData does not identify a map
/// or document how Vector3.offset relates the scanner, robot and map coordinate frames.
public struct LidarScan: Equatable, Sendable {
    public let samples: Int
    public let validSamples: Int
    public let nearest: Float?
    public let farthest: Float?

    public init(data: Data) throws {
        var options = JSONDecodingOptions()
        options.ignoreUnknownFields = true
        let message = try Woosh_Robot_ScannerData(jsonUTF8Data: data, options: options)
        samples = message.ranges.count
        var count = 0
        var low: Float?
        var high: Float?
        for value in message.ranges where value.isFinite && value > 0 {
            if message.rangeMin > 0 && value < message.rangeMin { continue }
            if message.rangeMax > 0 && value > message.rangeMax { continue }
            count += 1
            low = min(low ?? value, value)
            high = max(high ?? value, value)
        }
        validSamples = count
        nearest = low
        farthest = high
    }
}

/// The dimensions and byte counts are specified. The raster encoding needs a physical robot sample.
public struct MapBuildFrame: Equatable, Sendable {
    public let width: UInt32
    public let height: UInt32
    public let payloadBytes: Int

    public init(data: Data) throws {
        var options = JSONDecodingOptions()
        options.ignoreUnknownFields = true
        let message = try Woosh_Robot_BuildMapData(jsonUTF8Data: data, options: options)
        width = message.width
        height = message.height
        payloadBytes = message.mapData.count
    }
}
