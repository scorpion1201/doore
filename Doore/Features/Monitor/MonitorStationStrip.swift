import SwiftUI
import WooshKit

struct MonitorStationPages {
    let count: Int
    let perPage: Int
    let chipWidth: CGFloat

    init(count: Int, width: CGFloat, compactLabelWidth: CGFloat? = nil) {
        self.count = count
        let gap = compactLabelWidth == nil ? DooreSize.smallGap : DooreSize.tightGap
        let available = max(0, width - 2 * (DooreSize.tapTarget + gap))
        if let compactLabelWidth {
            let preferred = min(DooreSize.stationMaxWidth, max(DooreSize.tapTarget, ceil(compactLabelWidth) + 2 * gap))
            perPage = max(1, min(count, Int((available + gap) / (preferred + gap))))
        } else {
            perPage = max(1, Int(ceil((available + gap) / (DooreSize.stationMaxWidth + gap))))
        }
        chipWidth = min(DooreSize.stationMaxWidth, max(0, (available + gap) / CGFloat(perPage) - gap))
    }

    var pageCount: Int { (count + perPage - 1) / perPage }

    func indices(on page: Int) -> Range<Int> {
        let start = min(count, max(0, page) * perPage)
        return start..<min(count, start + perPage)
    }
}

struct MonitorStationStrip: View {
    let stations: [Station]
    let selected: String?
    let select: (String) -> Void

    @Environment(\.compactLayout) private var compact
    @State private var visiblePage: Int? = 0
    @ScaledMetric private var chipHeight = DooreSize.stationChipHeight
    @ScaledMetric private var compactChipHeight = DooreSize.compactStationChipHeight
    @ScaledMetric private var compactFontSize = DooreSize.smallFont

    private var compactLabelWidth: CGFloat? {
        guard compact else { return nil }
        #if os(iOS)
        let font = UIFont.systemFont(ofSize: compactFontSize, weight: .semibold)
        #else
        let font = NSFont.systemFont(ofSize: compactFontSize, weight: .semibold)
        #endif
        return stations.lazy.map { ($0.number as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
    }

    var body: some View {
        GeometryReader { geometry in
            let gap = compact ? DooreSize.tightGap : DooreSize.smallGap
            let pages = MonitorStationPages(count: stations.count, width: geometry.size.width, compactLabelWidth: compactLabelWidth)
            let current = min(visiblePage ?? 0, max(0, pages.pageCount - 1))
            let selectedPage = stations.firstIndex { $0.number == selected }.map { $0 / pages.perPage }
            HStack(spacing: gap) {
                arrow("chevron.left", "이전 스테이션", to: current - 1, pages: pages)
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 0) {
                        ForEach(0..<pages.pageCount, id: \.self) { page in
                            HStack(spacing: gap) {
                                ForEach(stations[pages.indices(on: page)], id: \.number) { station in
                                    chip(station.number, width: pages.chipWidth)
                                }
                            }
                            .containerRelativeFrame(.horizontal, alignment: .leading)
                            .id(page)
                        }
                    }.scrollTargetLayout()
                }
                .scrollIndicators(.hidden)
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: $visiblePage, anchor: .leading)
                arrow("chevron.right", "다음 스테이션", to: current + 1, pages: pages)
            }
            .onChange(of: selectedPage, initial: true) { _, page in
                if let page { visiblePage = page }
            }
            .onChange(of: selected) { _, _ in
                if let selectedPage { visiblePage = selectedPage }
            }
            .onChange(of: pages.pageCount) { _, count in
                if let visiblePage, visiblePage >= count { self.visiblePage = current }
            }
        }
        .frame(height: max(DooreSize.tapTarget, compact ? compactChipHeight : chipHeight))
    }

    private func arrow(_ symbol: String, _ label: LocalizedStringKey, to page: Int, pages: MonitorStationPages) -> some View {
        Button {
            withAnimation { visiblePage = page }
        } label: {
            Image(systemName: symbol)
                .frame(width: DooreSize.tapTarget, height: DooreSize.tapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .disabled(!(0..<pages.pageCount).contains(page))
    }

    private func chip(_ number: String, width: CGFloat) -> some View {
        Button { select(number) } label: {
            Text(verbatim: number)
                .fontWeight(selected == number ? .semibold : .regular)
                .lineLimit(1)
                .frame(width: width, height: compact ? compactChipHeight : chipHeight)
                .background(selected == number ? DooreColor.primaryTint : DooreColor.surface, in: Capsule())
                .overlay { Capsule().strokeBorder(DooreColor.primary, lineWidth: DooreSize.outline) }
                .frame(minHeight: DooreSize.tapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected == number ? .isSelected : [])
    }
}
