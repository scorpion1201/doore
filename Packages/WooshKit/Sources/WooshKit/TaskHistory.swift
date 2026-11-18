import Foundation
import SwiftProtobuf

public struct TaskHistoryPage: Sendable {
    enum HistoryError: Error { case invalidPage }
    public static let pageSize = 25
    public let total: Int
    public let tasks: [Woosh_Robot_Count_Task]

    static func request(page: Int) throws -> Woosh_Robot_CountData {
        guard page >= 1, let number = Int32(exactly: page) else { throw HistoryError.invalidPage }
        // The original UI numbers pages from 1. Keep the wire convention isolated for site verification.
        return Woosh_Robot_CountData.with {
            $0.reqType = .kGet
            $0.countType = .kTask
            $0.taskPage = number
        }
    }

    init(data: Data) throws {
        var options = JSONDecodingOptions()
        options.ignoreUnknownFields = true
        let response = try Woosh_Robot_CountDataResponse(jsonUTF8Data: data, options: options)
        guard response.taskQty >= 0 else { throw CocoaError(.coderReadCorrupt) }
        tasks = response.tasks.ts
        total = max(tasks.count, Int(response.taskQty))
    }
}

extension RobotSession {
    public func taskHistory(page: Int) async throws -> TaskHistoryPage {
        let request = try TaskHistoryPage.request(page: page)
        let data = try await readOnly(type: Woosh_Robot_CountData.protoMessageName, body: request.jsonUTF8Data())
        return try TaskHistoryPage(data: data)
    }
}
