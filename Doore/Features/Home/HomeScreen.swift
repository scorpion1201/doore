import SwiftUI

enum WorkspacePage: Int, CaseIterable, Identifiable {
    case monitor = 1, map, task, settings, device, design
    var id: Self { self }

    var title: String {
        switch self {
        case .monitor: "모니터"
        case .map: "지도"
        case .task: "작업"
        case .settings: "설정"
        case .device: "장치"
        case .design: "설계"
        }
    }

    var symbol: String {
        switch self {
        case .monitor: "point.bottomleft.forward.to.point.topright.scurvepath"
        case .map: "map"
        case .task: "doc.text"
        case .settings: "gearshape"
        case .device: "dot.radiowaves.left.and.right"
        case .design: "pencil.and.outline"
        }
    }
}

struct HomeScreen: View {
    let open: (WorkspacePage) -> Void
    @Environment(\.compactLayout) private var compact
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        GeometryReader { geometry in
            let columns = compact ? 2 : 3
            let rows = compact ? 3 : 2
            let gap = compact ? DooreSize.compactGap : DooreSize.gap
            let width = max(0, (geometry.size.width - CGFloat(columns + 1) * gap) / CGFloat(columns))
            let tileWidth = compact ? width : min(width, DooreSize.tileWidth)
            let availableHeight = (geometry.size.height - CGFloat(rows + 1) * gap) / CGFloat(rows)
            let tileHeight = compact ? max(availableHeight, DooreSize.compactTileMinimum)
                                     : max(min(availableHeight, DooreSize.tileHeight), DooreSize.compactTileMinimum)
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(tileWidth), spacing: gap), count: columns),
                          spacing: gap) {
                    ForEach(WorkspacePage.allCases) { page in
                        Button { open(page) } label: {
                            ViewThatFits(in: .horizontal) {
                                HStack(spacing: compact ? DooreSize.smallGap : DooreSize.compactGap) {
                                    icon(page)
                                    Text(LocalizedStringKey(page.title)).fixedSize()
                                }
                                VStack(spacing: DooreSize.smallGap) {
                                    icon(page)
                                    Text(LocalizedStringKey(page.title)).multilineTextAlignment(.center)
                                }
                            }
                            .padding(DooreSize.smallGap)
                            .dooreFont(compact ? DooreSize.compactTileFont : DooreSize.tileFont)
                            .frame(maxWidth: .infinity, minHeight: tileHeight)
                            .background(DooreColor.surface, in: RoundedRectangle(cornerRadius: DooreSize.radius))
                            .contentShape(RoundedRectangle(cornerRadius: DooreSize.radius))
                        }
                        .buttonStyle(.plain)
                        .dooreHover()
                        .accessibilityIdentifier("home.tile.\(page.rawValue)")
                    }
                }
                .padding(.vertical, gap)
                .frame(maxWidth: .infinity, minHeight: geometry.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    private func icon(_ page: WorkspacePage) -> some View {
        let width = compact || typeSize.isAccessibilitySize ? DooreSize.compactTileIcon : DooreSize.tileIcon
        return Image(systemName: page.symbol)
            .resizable()
            .scaledToFit()
            .foregroundStyle(DooreColor.icon)
            .frame(width: width, height: width)
            .accessibilityHidden(true)
    }
}
