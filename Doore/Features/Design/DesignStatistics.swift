import SwiftUI
import WooshKit

extension RobotStore {
    func readTaskHistory(page: Int) async throws -> TaskHistoryPage {
        try await session.taskHistory(page: page)
    }
}

private struct HistoryRequest: Equatable {
    var token = UUID()
    let page: Int
    let robotID: String?
    let state: Int?
    let sortColumn: Int?
    let descending: Bool
}

struct DesignStatistics: View {
    @Environment(RobotStore.self) private var robot
    @Environment(\.compactLayout) private var compact
    @State private var chosenRobot: String?
    @State private var chosenState: Int?
    @State private var start = Calendar.current.startOfDay(for: Date())
    @State private var end = Date()
    @State private var request: HistoryRequest?
    @State private var rows: [Woosh_Robot_Count_Task] = []
    @State private var total: Int?
    @State private var page = 1
    @State private var pageText = "1"
    @State private var loading = false
    @State private var failure: String?
    @State private var robotRejectedQuery = false
    private let columns = ["ID", "로봇", "출발점", "목표점", "시작 시각", "종료 시각", "상태"]

    private var pageCount: Int { max(1, ((total ?? 0) + TaskHistoryPage.pageSize - 1) / TaskHistoryPage.pageSize) }

    var body: some View {
        VStack(spacing: DooreSize.smallGap) {
            Text("작업 이력").font(.headline)
            if compact {
                VStack {
                    HStack { filterPickers }
                    dates
                    HStack { queryButtons }
                }
            } else {
                ScrollView(.horizontal) { HStack { filterPickers; dates; queryButtons } }
            }
            ScrollView([.horizontal, .vertical]) {
                Grid(horizontalSpacing: DooreSize.compactGap, verticalSpacing: DooreSize.smallGap) {
                    GridRow {
                        ForEach(columns.indices, id: \.self) { i in
                            #if os(macOS)
                            Button {
                                run(page: 1, robotID: request?.robotID, state: request?.state, column: i,
                                    descending: request?.sortColumn == i ? !(request?.descending ?? false) : false)
                            } label: {
                                HStack {
                                    Text(LocalizedStringKey(columns[i]))
                                    if request?.sortColumn == i { Image(systemName: request?.descending == true ? "chevron.down" : "chevron.up") }
                                }.frame(maxWidth: .infinity, alignment: .leading)
                            }.buttonStyle(.plain).disabled(total == nil || loading || i == 2)
                            #else
                            Text(LocalizedStringKey(columns[i])).frame(maxWidth: .infinity, alignment: .leading)
                            #endif
                        }
                    }.fontWeight(.semibold).padding(.vertical, DooreSize.smallGap).background(DooreColor.well)
                    ForEach(rows.indices, id: \.self) { index in
                        let task = rows[index]
                        GridRow {
                            ForEach(columns.indices, id: \.self) { column in
                                if column == 6, let key = stateLabel(task.state.rawValue) {
                                    Text(LocalizedStringKey(key)).frame(maxWidth: .infinity, alignment: .leading)
                                } else {
                                    Text(verbatim: value(task, column)).frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }.monospacedDigit()
                        Divider()
                    }
                }.frame(minWidth: DooreSize.designGridWidth)
            }
            if loading {
                ProgressView("불러오는 중")
            } else if let failure {
                Group {
                    if robotRejectedQuery { Text(verbatim: failure) }
                    else { Text(LocalizedStringKey(failure)) }
                }.foregroundStyle(DooreColor.danger)
                Button("다시 시도") { repeatRequest(page) }.buttonStyle(DooreButtonStyle(.line))
            } else if robot.state != .ready {
                RobotRegionState(message: "로봇에 연결하면 작업 이력을 조회할 수 있습니다.")
            } else if total == nil {
                Text("상태를 고르고 조회를 누르세요.").foregroundStyle(DooreColor.inkSoft)
            } else if rows.isEmpty {
                Text("작업 이력이 없습니다.").foregroundStyle(DooreColor.inkSoft)
            }
            Spacer(minLength: 0)
            ScrollView(.horizontal) { pager }
        }
        .doorePanel()
        .onChange(of: robot.state) { _, next in if next != .ready { resetResults() } }
        .task(id: request) { if let request { await load(request) } }
    }

    @ViewBuilder private var filterPickers: some View {
        Picker("로봇", selection: $chosenRobot) {
            Text("전체").tag(String?.none)
            if let id = robot.number { Text(verbatim: robot.name ?? id).tag(Optional(id)) }
        }
        Picker("상태", selection: $chosenState) {
            Text("전체").tag(Int?.none)
            ForEach(0..<4, id: \.self) { id in Text(LocalizedStringKey(stateLabel(id) ?? "—")).tag(Optional(id)) }
        }
    }

    private var dates: some View {
        HStack(spacing: DooreSize.tightGap) {
            Text("기간")
            DatePicker("부터", selection: $start, displayedComponents: .date).labelsHidden()
            DatePicker("까지", selection: $end, displayedComponents: .date).labelsHidden()
        }
        // TimeBucket uses unlabeled 32-bit integers. Keep a site clock convention out of the request.
        .disabled(true)
        .help("로봇 이력 시각의 단위가 확인되면 기간으로 조회할 수 있습니다.")
        .accessibilityHint("로봇 이력 시각의 단위가 확인되면 기간으로 조회할 수 있습니다.")
    }

    @ViewBuilder private var queryButtons: some View {
        Button("지우기") { chosenRobot = nil; chosenState = nil }
            .buttonStyle(DooreButtonStyle(.quiet, small: true))
        Button("조회") { run(page: 1, robotID: chosenRobot, state: chosenState, column: nil, descending: false) }
            .buttonStyle(DooreButtonStyle(.primary, small: true)).disabled(robot.state != .ready || loading)
    }

    private var pager: some View {
        HStack(spacing: DooreSize.tightGap) {
            if let total { Text("전체 \(total)건") }
            TextField("쪽", text: $pageText)
                .dooreField().frame(width: DooreSize.tapTarget)
                .disabled(total == nil || loading)
                .onSubmit {
                    guard let newPage = Int(pageText), (1...pageCount).contains(newPage) else {
                        pageText = String(page)
                        return
                    }
                    repeatRequest(newPage)
                }
            Text("/ \(pageCount) 쪽")
            Button("처음") { repeatRequest(1) }.disabled(page <= 1 || loading)
            Button("이전") { repeatRequest(page - 1) }.disabled(page <= 1 || loading)
            Button("다음") { repeatRequest(page + 1) }.disabled(page >= pageCount || loading)
            Button("끝") { repeatRequest(pageCount) }.disabled(page >= pageCount || loading)
        }.buttonStyle(DooreButtonStyle(.quiet, small: true))
    }

    private func stateLabel(_ state: Int) -> String? {
        let labels = ["실행 중", "완료", "실패", "취소"]
        return labels.indices.contains(state) ? labels[state] : nil
    }

    private func value(_ task: Woosh_Robot_Count_Task, _ column: Int) -> String {
        switch column {
        case 0: String(task.taskID)
        case 1: task.commu == nil ? (robot.name ?? "—") : String(task.robotID)
        case 3: task.dest.isEmpty ? "—" : task.dest
        case 4: task.hasBucket ? String(task.bucket.start) : "—"
        case 5: task.hasBucket && task.end ? String(task.bucket.end) : "—"
        case 6: stateLabel(task.state.rawValue) ?? String(task.state.rawValue)
        default: "—"
        }
    }

    private func run(page: Int, robotID: String?, state: Int?, column: Int?, descending: Bool) {
        request = HistoryRequest(page: page, robotID: robotID, state: state, sortColumn: column, descending: descending)
    }

    private func repeatRequest(_ page: Int) {
        guard let request else { return }
        run(page: page, robotID: request.robotID, state: request.state, column: request.sortColumn, descending: request.descending)
    }

    private func resetResults() {
        request = nil
        loading = false
        failure = nil
        total = nil
        rows.removeAll()
        page = 1
        pageText = "1"
    }

    private func load(_ query: HistoryRequest) async {
        loading = true
        failure = nil
        defer { if request == query { loading = false } }
        do {
            let needsCollection = query.state != nil || query.robotID != nil || query.sortColumn != nil
            let first = try await robot.readTaskHistory(page: needsCollection ? 1 : query.page)
            var result = first.tasks
            var count = first.total
            if needsCollection {
                let last = (first.total + TaskHistoryPage.pageSize - 1) / TaskHistoryPage.pageSize
                if last >= 2 {
                    for page in 2...last {
                        try Task.checkCancellation()
                        let next = try await robot.readTaskHistory(page: page)
                        if next.tasks.isEmpty { break }
                        result += next.tasks
                    }
                }
                result = result.filter { task in
                    (query.state == nil || query.state == task.state.rawValue)
                        && (query.robotID == nil || query.robotID == (task.commu == nil ? robot.number : String(task.robotID)))
                }
                if let column = query.sortColumn {
                    result.sort { a, b in
                        let first = value(a, column), second = value(b, column)
                        let comparison = first.localizedStandardCompare(second)
                        return query.descending ? comparison == .orderedDescending : comparison == .orderedAscending
                    }
                }
                count = result.count
                result = Array(result.dropFirst((query.page-1) * TaskHistoryPage.pageSize).prefix(TaskHistoryPage.pageSize))
            }
            try Task.checkCancellation()
            guard request == query else { return }
            rows = result
            total = count
            page = query.page
            pageText = String(page)
        } catch is CancellationError {
        } catch {
            guard request == query else { return }
            let message = (error as? SessionError)?.errorDescription
            robotRejectedQuery = message != nil
            failure = message ?? "작업 이력을 받지 못했습니다."
        }
    }
}
