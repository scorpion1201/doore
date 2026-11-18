import SwiftUI
import ImageIO
import WooshKit
#if os(macOS)
import AppKit
#endif

struct MapOverlayMark {
    enum Kind { case station, field, path, free, wall, unknown, noGo, traffic }
    let points: [MapPose]
    let kind: Kind
    var label = ""
    var isSelected = false
    var stationType: String?
}

private struct MapBitmap {
    let base: CGImage
    let noGo: CGImage?
    let traffic: CGImage?

    static func image(_ data: Data?) -> CGImage? {
        guard let data, let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 32_768, height <= 32_768,
              width * height <= 64_000_000 else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    init?(map: MapModel?) {
        guard let image = Self.image(map?.imageData) else { return nil }
        base = image
        noGo = Self.image(map?.noGoData)
        traffic = Self.image(map?.trafficData)
    }
}

struct MapCanvasView: View {
    let map: MapModel?
    let pose: MapPose?
    @Binding var selected: String?
    var followsRobot = false
    var showsStations = true
    var showsRobot = true
    var showsOriginalGeometry = true
    var showsNavigationPath = true
    var layers: Set<String> = ["구역", "스테이션", "경로", "로봇", "주행 금지", "교통 통제"]
    var overlays: [MapOverlayMark] = []
    var onTap: ((MapPose) -> Void)?
    var onMove: ((MapPose, MapPose) -> Void)?
    var onInspect: ((MapPose) -> Void)?
    var onAddStroke: ((MapPose, MapPose) -> Void)?

    var onMoveRobot: ((MapPose) -> Void)?
    var onDraw: (([MapPose]) -> Void)?
    @State private var stroke: [MapPose] = []

    @Environment(RobotStore.self) private var robot
    @Environment(\.compactLayout) private var compact
    @State private var bitmap: MapBitmap?
    @State private var zoom = 1.0
    @State private var offset = CGSize.zero
    @State private var centerPoint: MapPose?
    @GestureState private var pan = CGSize.zero
    @GestureState private var magnification: CGFloat = 1
    @State private var draggedObject = false

    var body: some View {
        Group {
            if let map, let bitmap {
                GeometryReader { proxy in
                    let transform = Viewport(map: map, bitmap: bitmap, size: proxy.size,
                                             zoom: zoom * magnification, offset: offset + pan,
                                             center: followsRobot ? pose : centerPoint)
                    Canvas { context, _ in render(context, bitmap, transform) }
                        .background(DooreColor.mapUnknown)
                        .contentShape(Rectangle())
                        .gesture(taps(transform))
                        .simultaneousGesture(panning)
                        .simultaneousGesture(drawing(transform), including: onDraw == nil ? .none : .gesture)
                        .simultaneousGesture(magnifying)
                        .simultaneousGesture(moving(transform), including: onMove == nil && onMoveRobot == nil ? .none : .gesture)
                        .onContinuousHover { phase in
                            if case .active(let point) = phase, let hit = transform.pose(point) { onInspect?(hit) }
                        }
                        #if os(macOS)
                        .simultaneousGesture(modifiedDrag(transform, flag: .shift, action: onMove))
                        .simultaneousGesture(modifiedDrag(transform, flag: .option, action: onAddStroke))
                        .modifier(WheelZoom { zoom = clamped(zoom * exp($0 * 0.014)) })
                        #endif
                        .accessibilityLabel("지도")
                        .clipped()
                }
            } else {
                RobotRegionState(message: "로봇에 연결하면 지도와 스테이션이 여기에 표시됩니다.",
                                 empty: map == nil ? "표시할 지도가 없습니다." : "지도 이미지를 읽을 수 없습니다.")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(minHeight: DooreSize.mapMinimum)
        .onChange(of: map, initial: true) { old, new in
            if old?.id != new?.id { resetView() }
            if old != new || bitmap == nil { bitmap = MapBitmap(map: new) }
        }
        .onChange(of: selected) { _, number in
            centerPoint = map?.stations.first { $0.number == number }?.pose
            offset = .zero
        }
    }

    private func clamped(_ value: CGFloat) -> CGFloat { min(16, max(0.15, value)) }

    private func resetView() {
        offset = .zero
        zoom = 1
        centerPoint = nil
    }

    private var panning: some Gesture {
        DragGesture().updating($pan) { value, state, _ in
            if canPan { state = value.translation }
        }.onEnded { value in
            if canPan { offset = offset + value.translation }
            draggedObject = false
        }
    }

    private var canPan: Bool {
        #if os(macOS)
        if !NSEvent.modifierFlags.intersection([.shift, .option]).isEmpty { return false }
        #endif
        return !draggedObject && onDraw == nil
    }

    private func drawing(_ viewport: Viewport) -> some Gesture {
        DragGesture(minimumDistance: 0).onChanged { value in
            if let point = viewport.pose(value.location), stroke.last != point { stroke.append(point) }
        }.onEnded { _ in
            if !stroke.isEmpty { onDraw?(stroke) }
            stroke = []
        }
    }

    private var magnifying: some Gesture {
        MagnifyGesture().updating($magnification) { value, state, _ in state = value.magnification }
            .onEnded { zoom = clamped(zoom * $0.magnification) }
    }

    private func taps(_ viewport: Viewport) -> some Gesture {
        SpatialTapGesture(count: 2).exclusively(before: SpatialTapGesture())
            .onEnded { result in
                switch result {
                case .first: resetView()
                case .second(let tap):
                    guard let hit = viewport.pose(tap.location) else { return }
                    onInspect?(hit)
                    if let onTap { onTap(hit); return }
                    guard showsStations, layers.contains("스테이션") else { return }
                    let nearest = map?.stations.compactMap { station -> (String, CGFloat)? in
                        guard let point = station.pose.flatMap(viewport.point) else { return nil }
                        let distance = hypot(point.x - tap.location.x, point.y - tap.location.y)
                        return (station.number, distance)
                    }.min { $0.1 < $1.1 }
                    selected = nearest.flatMap { $0.1 <= DooreSize.tapTarget / 2 ? $0.0 : nil }
                }
            }
    }

    private func moving(_ viewport: Viewport) -> some Gesture {
        LongPressGesture().sequenced(before: DragGesture(minimumDistance: 0))
            .onChanged { phase in
                if case .second(true, _) = phase { draggedObject = true }
            }.onEnded { phase in
                defer { draggedObject = false }
                if case .second(true, let drag?) = phase,
                   let source = viewport.pose(drag.startLocation), let destination = viewport.pose(drag.location) {
                    if let onMoveRobot, let center = pose.flatMap(viewport.point),
                       hypot(center.x - drag.startLocation.x, center.y - drag.startLocation.y) <= DooreSize.tapTarget / 2 {
                        onMoveRobot(destination)
                    } else { onMove?(source, destination) }
                }
            }
    }

    #if os(macOS)
    private func modifiedDrag(_ viewport: Viewport, flag: EventModifiers,
                              action: ((MapPose, MapPose) -> Void)?) -> some Gesture {
        DragGesture().modifiers(flag).onEnded { drag in
            if let a = viewport.pose(drag.startLocation), let b = viewport.pose(drag.location) { action?(a, b) }
        }
    }
    #endif

    private func render(_ context: GraphicsContext, _ bitmap: MapBitmap, _ viewport: Viewport) {
        func image(_ cg: CGImage) {
            context.draw(Image(decorative: cg, scale: 1), in: viewport.rect)
        }
        image(bitmap.base)
        if layers.contains("주행 금지"), let mask = bitmap.noGo { image(mask) }
        if layers.contains("교통 통제"), let mask = bitmap.traffic { image(mask) }
        if showsOriginalGeometry && layers.contains("구역") {
            for field in map?.fields ?? [] { draw(.init(points: field, kind: .field), context, viewport) }
        }
        if layers.contains("경로") {
            if showsOriginalGeometry {
                for guide in map?.guides ?? [] { draw(.init(points: guide, kind: .path), context, viewport) }
            }
            if showsNavigationPath, let map, map.id == robot.currentMapID {
                context.stroke(viewport.path(robot.navPath), with: .color(DooreColor.primary),
                               style: StrokeStyle(lineWidth: DooreSize.lineWidth, dash: [DooreSize.dash]))
            }
        }
        if showsStations && layers.contains("스테이션") {
            for station in map?.stations ?? [] {
                guard let point = station.pose else { continue }
                let isSelected = selected == station.number
                draw(.init(points: [point], kind: .station, label: station.number,
                           isSelected: isSelected, stationType: station.kind), context, viewport)
            }
        }
        for overlay in overlays {
            switch overlay.kind {
            case .station where !layers.contains("스테이션"), .field where !layers.contains("구역"),
                 .path where !layers.contains("경로"), .noGo where !layers.contains("주행 금지"),
                 .traffic where !layers.contains("교통 통제"): continue
            default: draw(overlay, context, viewport)
            }
        }
        if showsRobot && layers.contains("로봇"), let pose, let center = viewport.point(pose) {
            var rotated = context
            rotated.translateBy(x: center.x, y: center.y)
            rotated.rotate(by: .radians(-pose.theta))
            let w = DooreSize.robotMarker
            rotated.fill(Path(roundedRect: CGRect(x: -w/2, y: -w/3, width: w, height: w * 2/3),
                              cornerRadius: DooreSize.tightGap), with: .color(DooreColor.mapWall))
            var chevron = Path()
            chevron.move(to: CGPoint(x: -w/8, y: -w/5))
            chevron.addLine(to: CGPoint(x: w/8, y: 0))
            chevron.addLine(to: CGPoint(x: -w/8, y: w/5))
            rotated.stroke(chevron, with: .color(DooreColor.surface), lineWidth: DooreSize.lineWidth)
        }
        if layers.contains("자"), let resolution = map?.resolution {
            let width = DooreSize.rulerLength
            let end = CGPoint(x: DooreSize.gap + width, y: viewport.size.height - DooreSize.gap)
            var path = Path()
            path.move(to: CGPoint(x: end.x - width, y: end.y))
            path.addLine(to: end)
            context.stroke(path, with: .color(DooreColor.ink), lineWidth: DooreSize.lineWidth)
            let meters = Double(width / viewport.scale) * resolution
            context.draw(Text(verbatim: String(format: "%.2f m", meters)).foregroundStyle(DooreColor.ink),
                         at: end, anchor: .bottomTrailing)
        }
    }

    private func draw(_ mark: MapOverlayMark, _ ctx: GraphicsContext, _ view: Viewport) {
        guard let first = mark.points.first.flatMap(view.point) else { return }
        let path = view.path(mark.points, closed: mark.kind == .field)
        switch mark.kind {
        case .field:
            ctx.fill(path, with: .color(DooreColor.primaryTint.opacity(0.7)))
            ctx.stroke(path, with: .color(DooreColor.primary), lineWidth: DooreSize.lineWidth)
        case .station:
            let w = DooreSize.marker
            let marker = Path(roundedRect: CGRect(x: first.x - w / 2, y: first.y - w / 2, width: w, height: w),
                              cornerRadius: DooreSize.tightGap)
            ctx.fill(marker, with: .color(DooreColor.primaryTint))
            ctx.stroke(marker, with: .color(mark.isSelected ? DooreColor.primary : DooreColor.lineStrong),
                       style: StrokeStyle(lineWidth: DooreSize.lineWidth, dash: mark.isSelected ? [DooreSize.dash] : []))
            if !compact, !mark.label.isEmpty {
                let label: Text
                if mark.isSelected, let type = mark.stationType {
                    label = Text(verbatim: "[") + Text(LocalizedStringKey(type)) + Text(verbatim: "]" + mark.label)
                } else {
                    label = Text(verbatim: mark.label)
                }
                ctx.draw(label.font(.body).foregroundStyle(mark.isSelected ? DooreColor.danger : DooreColor.ink),
                         at: CGPoint(x: first.x, y: first.y + w/2), anchor: .top)
            }
        case .path:
            ctx.stroke(path, with: .color(DooreColor.good), lineWidth: DooreSize.lineWidth)
        default:
            let color: Color
            switch mark.kind {
            case .free: color = DooreColor.mapFree
            case .wall: color = DooreColor.mapWall
            case .noGo: color = DooreColor.danger
            case .traffic: color = DooreColor.primary
            default: color = DooreColor.mapUnknown
            }
            if mark.points.count == 1 {
                let w = DooreSize.strokeWidth
                ctx.fill(Path(ellipseIn: CGRect(x: first.x-w/2, y: first.y-w/2, width: w, height: w)), with: .color(color))
            } else {
                ctx.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: DooreSize.strokeWidth, lineCap: .round))
            }
        }
    }
}

private struct Viewport {
    let map: MapModel
    let size: CGSize
    let scale: CGFloat
    let rect: CGRect
    let height: CGFloat

    init(map: MapModel, bitmap: MapBitmap, size: CGSize, zoom: CGFloat, offset: CGSize, center: MapPose?) {
        self.map = map
        self.size = size
        let width = CGFloat(bitmap.base.width)
        let height = CGFloat(bitmap.base.height)
        self.height = height
        let scale = max(0.0001, min(size.width / width, size.height / height) * zoom)
        self.scale = scale
        let focus = center.flatMap { map.pixel(for: $0, height: height) }
        rect = CGRect(x: size.width/2 - (focus?.x ?? width/2) * scale + offset.width,
                      y: size.height/2 - (focus?.y ?? height/2) * scale + offset.height,
                      width: width * scale, height: height * scale)
    }

    func point(_ pose: MapPose) -> CGPoint? {
        guard let pixel = map.pixel(for: pose, height: height) else { return nil }
        return CGPoint(x: rect.minX + pixel.x * scale, y: rect.minY + pixel.y * scale)
    }

    func pose(_ point: CGPoint) -> MapPose? {
        guard rect.contains(point) else { return nil }
        return map.world(xPixel: (point.x - rect.minX)/scale, yPixel: (point.y - rect.minY)/scale, height: height)
    }

    func path(_ points: [MapPose], closed: Bool = false) -> Path {
        var path = Path()
        for (index, point) in points.compactMap(point).enumerated() {
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        if closed { path.closeSubpath() }
        return path
    }
}

private extension CGSize {
    static func + (lhs: CGSize, rhs: CGSize) -> CGSize {
        CGSize(width: lhs.width + rhs.width, height: lhs.height + rhs.height)
    }
}

#if os(macOS)
private struct WheelZoom: ViewModifier {
    let onScroll: (CGFloat) -> Void
    @State private var monitor: Any?

    func body(content: Content) -> some View {
        content.onHover { inside in
            remove()
            if inside {
                monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
                    guard event.window?.isKeyWindow == true else { return event }
                    onScroll(event.scrollingDeltaY)
                    return nil
                }
            }
        }.onDisappear { remove() }
    }

    private func remove() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
#endif

struct MapThumbnail: View {
    let data: Data?
    @State private var image: CGImage?
    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 1).resizable().interpolation(.none).scaledToFit()
            } else { DooreColor.mapUnknown }
        }.frame(width: DooreSize.mapPreviewWidth, height: DooreSize.mapPreviewHeight)
            .onChange(of: data, initial: true) { _, new in image = MapBitmap.image(new) }
    }
}
