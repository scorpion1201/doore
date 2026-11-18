import Foundation
import XCTest
@testable import WooshKit
import WooshKitTesting

final class TaskHistoryTests: XCTestCase {
    func testRequestsOnePageOfTasksOnly() throws {
        let request = try TaskHistoryPage.request(page: 3)
        XCTAssertEqual(request.taskPage, 3)
        XCTAssertEqual(request.reqType, .kGet)
        XCTAssertEqual(request.countType, .kTask)
        XCTAssertFalse(request.hasBucket)
        XCTAssertThrowsError(try TaskHistoryPage.request(page: 0))
    }

    func testReadHistoryUsesReadyConnectionAndPropagatesRobotError() async throws {
        let transport = FakeRobotTransport()
        let session = RobotSession(transport: transport)
        try await session.connect(to: .init(host: "192.0.2.8"))
        let type = Woosh_Robot_CountData.protoMessageName
        await transport.enqueue(.success(Data(#"{"tasks":{"ts":[{"id":3,"dest":"A1","state":1}]},"taskQty":27}"#.utf8)), for: type)
        let page = try await session.taskHistory(page: 2)
        XCTAssertEqual(page.total, 27)
        XCTAssertEqual(page.tasks.first?.id, 3)
        let calls = await transport.calls
        guard case let .request(actualType, body) = calls.last else { return XCTFail("Missing history request") }
        XCTAssertEqual(actualType, type)
        XCTAssertEqual(try Woosh_Robot_CountData(jsonUTF8Data: body).taskPage, 2)
        await transport.enqueue(.rejected("History disabled"), for: type)
        do {
            _ = try await session.taskHistory(page: 1)
            XCTFail("A rejection must reach the caller")
        } catch { XCTAssertEqual(error as? SessionError, .rejected("History disabled")) }
        await session.disconnect()
    }

    func testDecodeEmptyAndPopulatedPagesIncludingUnknownFields() throws {
        XCTAssertTrue(try TaskHistoryPage(data: Data("{}".utf8)).tasks.isEmpty)
        let body = Data(#"{"tasks":{"ts":[{"id":9,"taskId":"123","dest":"A1","state":"kCompleted","bucket":{"start":100,"end":140}}]},"taskQty":31,"future":true}"#.utf8)
        let result = try TaskHistoryPage(data: body)
        XCTAssertEqual(result.total, 31)
        XCTAssertEqual(result.tasks.first?.dest, "A1")
        XCTAssertEqual(result.tasks.first?.bucket.start, 100)
        XCTAssertEqual(result.tasks.first?.state, .kCompleted)
        XCTAssertThrowsError(try TaskHistoryPage(data: Data(#"{"taskQty":-2}"#.utf8)))
    }
}
