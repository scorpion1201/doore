import SwiftUI
import WooshKit

struct DesignTaskSets: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SceneEditingWorkspace.self) private var workspace
    @State private var editing: DraftTaskSet?
    @State private var deleting: DraftTaskSet?

    var body: some View {
        VStack(spacing: DooreSize.compactGap) {
            Text("작업 묶음").font(.headline)
            List(workspace.draft.taskSets) { set in
                HStack {
                    VStack(alignment: .leading) {
                        Text(verbatim: set.content.base.name)
                        Text("작업 \(set.content.tasks.count)개")
                    }
                    Spacer()
                    Button("수정") { editing = set }.buttonStyle(DooreButtonStyle(.quiet, small: true))
                    Button("삭제") { deleting = set }.buttonStyle(DooreButtonStyle(.danger, small: true))
                }
            }.frame(minHeight: DooreSize.mapMinimum)
            HStack {
                Button("닫기") { dismiss() }.buttonStyle(DooreButtonStyle(.quiet))
                Button("작업 묶음 추가") {
                    var draft = DraftTaskSet(repeating: Woosh_Task_RepeatTask())
                    let ids = Set(workspace.draft.taskSets.map { $0.content.base.id })
                    var candidate: Int32 = 1
                    while ids.contains(candidate), candidate < Int32.max { candidate += 1 }
                    draft.content.base.id = candidate
                    editing = draft
                }.buttonStyle(DooreButtonStyle(.primary))
            }
        }.padding(DooreSize.dialogPadding)
        .sheet(item: $editing) { set in
            DesignTaskSetForm(set: set, stations: workspace.draft.items.filter { $0.kind == .point }.map(\.number)) { value in
                workspace.draft.put(value)
                editing = nil
            }
        }
        .alert("작업 묶음 삭제", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
               presenting: deleting) { set in
            Button("취소", role: .cancel) {}
            Button("확인", role: .destructive) { workspace.draft.deleteTaskSet(set.id) }
        } message: { set in Text("\(set.content.base.name) 작업 묶음을 삭제할까요?") }
    }
}

private struct DesignTaskSetForm: View {
    @Environment(\.dismiss) private var dismiss
    @State var set: DraftTaskSet
    let stations: [String]
    let save: (DraftTaskSet) -> Void
    @State private var taskIndex: Int?
    @State private var confirmDelete = false
    @State private var robots = ""

    private var assignedRobots: [UInt32]? {
        if robots.trimmingCharacters(in: .whitespaces).isEmpty { return [] }
        let strings = robots.split(separator: ",", omittingEmptySubsequences: false)
        let numbers = strings.compactMap { UInt32($0.trimmingCharacters(in: .whitespaces)) }
        return strings.count == numbers.count ? numbers : nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DooreSize.smallGap) {
                Text("작업 묶음").font(.headline)
                LabeledContent("이름") { TextField("이름", text: $set.content.base.name).dooreField() }
                if let info = set.repeatInfo {
                    LabeledContent("반복 횟수") {
                        TextField("반복 횟수", value: Binding(get: { set.repeatInfo?.times ?? info.times },
                                  set: { set.repeatInfo?.times = $0 }), format: .number).dooreField()
                    }
                }
                LabeledContent("우선순위") { TextField("우선순위", value: $set.content.base.priority, format: .number).dooreField() }
                Picker("로봇 종류", selection: $set.content.base.rtype) {
                    ForEach(Woosh_Robot_Type.allCases, id: \.rawValue) { type in
                        if type == .kTypeUndefined { Text("전체").tag(type) }
                        else { Text(verbatim: String(describing: type)).tag(type) }
                    }
                }
                LabeledContent("지정 로봇") { TextField("로봇 번호", text: $robots).dooreField() }
                Divider()
                Text("작업 목록").fontWeight(.semibold)
                ForEach(set.content.tasks.indices, id: \.self) { index in
                    Button {
                        taskIndex = index
                    } label: {
                        HStack {
                            Text(verbatim: String(index + 1))
                            Text(verbatim: set.content.tasks[index].base.markNo)
                            Spacer()
                            if index == taskIndex { Image(systemName: "checkmark") }
                        }
                    }.buttonStyle(DooreButtonStyle(index == taskIndex ? .line : .quiet, small: true, fullWidth: true))
                }
                HStack {
                    Button("작업 추가") {
                        var task = Woosh_Task_WooshTask()
                        task.base.type = .kPick
                        task.base.direction = .kFeeding
                        task.base.markNo = stations.first ?? ""
                        let ids = Set(set.content.tasks.map { $0.base.id })
                        var id: Int32 = 1
                        while ids.contains(id), id < Int32.max { id += 1 }
                        task.base.id = id
                        set.content.tasks.append(task)
                        taskIndex = set.content.tasks.count - 1
                    }.disabled(stations.isEmpty)
                    Button("삭제") { confirmDelete = true }.disabled(taskIndex == nil)
                    DesignIconButton(title: "위로", icon: "arrow.up") { move(-1) }.disabled((taskIndex ?? 0) <= 0)
                    DesignIconButton(title: "아래로", icon: "arrow.down") { move(1) }
                        .disabled(taskIndex == nil || (taskIndex ?? 0) >= set.content.tasks.count - 1)
                }.buttonStyle(DooreButtonStyle(.quiet, small: true))
                if let index = taskIndex, set.content.tasks.indices.contains(index) {
                    taskForm(index)
                }
                if set.callInfo != nil { pager }
                HStack {
                    Button("취소") { dismiss() }.buttonStyle(DooreButtonStyle(.quiet))
                    Button("확인") {
                        guard let assignedRobots else { return }
                        set.content.base.robots = assignedRobots
                        save(set)
                        dismiss()
                    }.buttonStyle(DooreButtonStyle(.primary))
                        .disabled(set.content.base.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                  || assignedRobots == nil || set.content.tasks.isEmpty
                                  || (set.repeatInfo?.times ?? 0) < -1 || set.content.tasks.contains { $0.base.waitTime < -1 }
                                  || invalidCaller)
                }
            }.padding(DooreSize.dialogPadding)
        }
        .onAppear {
            robots = set.content.base.robots.map { String($0) }.joined(separator: ", ")
            if !set.content.tasks.isEmpty { taskIndex = 0 }
        }
        .alert("선택한 작업을 삭제할까요?", isPresented: $confirmDelete) {
            Button("취소", role: .cancel) {}
            Button("확인", role: .destructive) {
                guard let index = taskIndex, set.content.tasks.indices.contains(index) else { return }
                set.content.tasks.remove(at: index)
                taskIndex = set.content.tasks.isEmpty ? nil : min(index, set.content.tasks.count - 1)
            }
        }
    }

    private func taskForm(_ index: Int) -> some View {
        let task = $set.content.tasks[index]
        let current = set.content.tasks[index]
        let targets = Set(stations + [current.base.markNo]).filter { !$0.isEmpty }.sorted()
        return VStack(alignment: .leading) {
            Picker("목표점", selection: task.base.markNo) { ForEach(targets, id: \.self) { Text(verbatim: $0).tag($0) } }
            Picker("종류", selection: task.base.type) {
                Text("픽").tag(Woosh_Task_Type.kPick)
                Text("주차").tag(Woosh_Task_Type.kParking)
                Text("충전").tag(Woosh_Task_Type.kCharge)
                Text("운반").tag(Woosh_Task_Type.kCarry)
            }
            Picker("방향", selection: task.base.direction) {
                Text("적재").tag(Woosh_Task_Direction.kFeeding)
                Text("하역").tag(Woosh_Task_Direction.kCutting)
            }
            LabeledContent("대기 시간") { TextField("대기 시간", value: task.base.waitTime, format: .number).dooreField() }
            Toggle("건너뛸 수 있음", isOn: task.consta.canSkip)
            Toggle("실패 시 재실행", isOn: task.consta.failRedo)
            Toggle("실패 시 작업 묶음 종료", isOn: task.consta.failEnd)
            Toggle("취소 시 작업 묶음 종료", isOn: task.consta.cancelEnd)
            Toggle("실행 중 취소 불가", isOn: task.base.cannotCancel)
        }
    }

    private var invalidCaller: Bool {
        return set.callInfo?.callInfo.events.contains { $0.caller.macAddr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } == true
    }

    private var pager: some View {
        VStack(alignment: .leading) {
            Text("호출기 연결").fontWeight(.semibold)
            let count = set.callInfo?.callInfo.events.count ?? 0
            ForEach(0..<count, id: \.self) { index in
                LabeledContent("MAC 주소") {
                    TextField("MAC 주소", text: Binding(get: { set.callInfo?.callInfo.events[index].caller.macAddr ?? "" },
                        set: { set.callInfo?.callInfo.events[index].caller.macAddr = $0 })).dooreField()
                }
                LabeledContent("버튼 ID") {
                    TextField("버튼 ID", value: Binding(get: { set.callInfo?.callInfo.events[index].caller.keyID ?? 0 },
                        set: { set.callInfo?.callInfo.events[index].caller.keyID = $0 }), format: .number).dooreField()
                }
            }
            Picker("조건", selection: Binding(get: { set.callInfo?.callInfo.type ?? .kCallTypeUndefined },
                                             set: { set.callInfo?.callInfo.type = $0 })) {
                Text(verbatim: "AND").tag(Woosh_Task_CallInfo.CallType.kAnd)
                Text(verbatim: "OR").tag(Woosh_Task_CallInfo.CallType.kOr)
            }
        }
    }

    private func move(_ distance: Int) {
        guard let from = taskIndex else { return }
        let to = from + distance
        guard set.content.tasks.indices.contains(from), set.content.tasks.indices.contains(to) else { return }
        set.content.tasks.swapAt(from, to)
        taskIndex = to
    }
}
