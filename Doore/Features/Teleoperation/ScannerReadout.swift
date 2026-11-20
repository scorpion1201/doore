import SwiftUI
import WooshKit

private struct FeedInterest: ViewModifier {
    let feeds: Set<RobotFeed>
    @Environment(RobotStore.self) private var robot
    @State private var owner = UUID()
    @State private var visible = false

    func body(content: Content) -> some View {
        content
            .onAppear {
                visible = true
                robot.feeds.update(owner, wants: feeds)
            }
            .onChange(of: feeds) { _, next in
                if visible { robot.feeds.update(owner, wants: next) }
            }
            .onDisappear {
                visible = false
                robot.feeds.update(owner, wants: [])
            }
    }
}

extension View {
    func sensorFeeds(_ feeds: Set<RobotFeed>) -> some View { modifier(FeedInterest(feeds: feeds)) }
}

struct ScannerReadout: View {
    @Environment(RobotStore.self) private var robot

    var body: some View {
        if let scan = robot.feeds.scan {
            HStack {
                Text("라이다")
                Text("유효 측정값")
                Text(verbatim: "\(scan.validSamples)/\(scan.samples)").monospacedDigit()
                if let nearest = scan.nearest, let farthest = scan.farthest {
                    Text(verbatim: String(format: "%.2f – %.2f m", nearest, farthest)).monospacedDigit()
                }
            }.accessibilityElement(children: .combine)
        } else if robot.feeds.failures.contains(.scannerData) {
            Text("라이다 구독에 실패했습니다.").foregroundStyle(DooreColor.danger)
        } else {
            Text("라이다 데이터를 기다리는 중입니다.").foregroundStyle(DooreColor.inkSoft)
        }
    }
}
