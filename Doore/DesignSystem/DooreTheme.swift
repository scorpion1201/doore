import SwiftUI

enum DooreColor {
    static let background = Color("DooreBackground")
    static let surface = Color("DooreSurface")
    static let well = Color("DooreWell")
    static let tab = Color("DooreTab")
    static let ink = Color("DooreInk")
    static let inkSoft = Color("DooreInkSoft")
    static let line = Color("DooreLine")
    static let lineStrong = Color("DooreLineStrong")
    static let icon = Color("DooreIcon")
    static let primary = Color("DoorePrimary")
    static let primaryInk = surface
    static let primaryTint = Color("DoorePrimaryTint")
    static let danger = Color("DooreDanger")
    static let dangerInk = surface
    static let quiet = Color("DooreQuiet")
    static let good = Color("DooreGood")
    static let warn = Color("DooreWarn")
    static let mapFree = surface
    static let mapWall = Color("DooreMapWall")
    static let mapUnknown = Color("DooreMapUnknown")
    static let scrim = Color("DooreScrim")
}

enum DooreSize {
    static let gap: CGFloat = 20
    static let compactGap: CGFloat = 16
    static let panelPadding: CGFloat = 20
    static let compactPanelPadding: CGFloat = 12
    static let smallGap: CGFloat = 8
    static let tightGap: CGFloat = 4
    static let radius: CGFloat = 20
    static let rowRadius: CGFloat = 10
    static let squareRadius: CGFloat = 11
    static let fieldRadius: CGFloat = 5
    static let fieldHeight: CGFloat = 39
    static let buttonHeight: CGFloat = 44
    static let smallButtonHeight: CGFloat = 34
    static let tapTarget: CGFloat = 44
    static let hairline: CGFloat = 1
    static let outline: CGFloat = 2
    static let radioRing: CGFloat = 6
    static let radioDiameter: CGFloat = 20
    static let sidePanel: CGFloat = 400
    static let toolColumn: CGFloat = 176
    static let tabColumn: CGFloat = 200
    static let defaultWidth: CGFloat = 1280
    static let defaultHeight: CGFloat = 800
    static let compactLandscapeHeight: CGFloat = 480
    static let tileWidth: CGFloat = 330
    static let tileHeight: CGFloat = 250
    static let compactTileMinimum: CGFloat = 108
    static let compactTileIcon: CGFloat = 51
    static let tileIcon: CGFloat = 90
    static let compactTileFont: CGFloat = 21
    static let tileFont: CGFloat = 30
    static let statusHeight: CGFloat = 80
    static let compactStatusHeight: CGFloat = 46
    static let statusFont: CGFloat = 22
    static let smallFont: CGFloat = 16
    static let buttonFont: CGFloat = 18
    static let bodyFont: CGFloat = 17
    static let dialogFont: CGFloat = 24
    static let dialogPadding: CGFloat = 24
    static let dialogWidth: CGFloat = 896
    static let addressFieldWidth: CGFloat = 160
    static let dialogScrollLimit: CGFloat = 400
    static let homeIcon: CGFloat = 36
    static let compactHomeIcon: CGFloat = 21
    static let statusIcon: CGFloat = 24
    static let separatorHeight: CGFloat = 30
}

private struct CompactLayoutKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var compactLayout: Bool {
        get { self[CompactLayoutKey.self] }
        set { self[CompactLayoutKey.self] = newValue }
    }
}

enum DooreButtonKind {
    case primary, danger, quiet, line
}

struct DooreButtonStyle: ButtonStyle {
    let kind: DooreButtonKind
    var square: Bool
    var small: Bool
    var fullWidth: Bool
    @Environment(\.isEnabled) private var enabled
    @Environment(\.compactLayout) private var compact

    init(_ kind: DooreButtonKind, square: Bool = false, small: Bool = false, fullWidth: Bool = false) {
        self.kind = kind
        self.square = square
        self.small = small
        self.fullWidth = fullWidth
    }

    func makeBody(configuration: Configuration) -> some View {
        let height = small ? DooreSize.smallButtonHeight : DooreSize.buttonHeight
        let shape = RoundedRectangle(cornerRadius: square ? DooreSize.squareRadius : height / 2)
        return configuration.label
            .dooreFont(small || compact ? DooreSize.smallFont : DooreSize.buttonFont)
            .multilineTextAlignment(.center)
            .padding(.horizontal, small ? DooreSize.compactPanelPadding : DooreSize.compactGap)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: height)
            .foregroundStyle(foreground)
            .background(fill, in: shape)
            .overlay {
                if kind == .line { shape.strokeBorder(DooreColor.primary, lineWidth: DooreSize.outline) }
            }
            .opacity(configuration.isPressed ? 0.75 : (enabled ? 1 : 0.5))
            .dooreHover()
            .frame(minWidth: DooreSize.tapTarget, minHeight: DooreSize.tapTarget)
            .contentShape(Rectangle())
    }

    private var foreground: Color {
        switch kind {
        case .primary: DooreColor.primaryInk
        case .danger: DooreColor.dangerInk
        case .quiet: DooreColor.ink
        case .line: DooreColor.primary
        }
    }

    private var fill: Color {
        switch kind {
        case .primary: DooreColor.primary
        case .danger: DooreColor.danger
        case .quiet: DooreColor.quiet
        case .line: DooreColor.surface
        }
    }
}

private struct DooreFont: ViewModifier {
    @ScaledMetric var size: CGFloat
    let weight: Font.Weight

    init(size: CGFloat, weight: Font.Weight) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: .body)
        self.weight = weight
    }

    func body(content: Content) -> some View {
        content.font(.system(size: size, weight: weight))
    }
}

private struct Panel: ViewModifier {
    @Environment(\.compactLayout) private var compact
    func body(content: Content) -> some View {
        content.padding(compact ? DooreSize.compactPanelPadding : DooreSize.panelPadding)
            .background(DooreColor.surface, in: RoundedRectangle(cornerRadius: DooreSize.radius))
    }
}

private struct FieldAppearance: ViewModifier {
    func body(content: Content) -> some View {
        content.textFieldStyle(.plain)
            .dooreFont(DooreSize.bodyFont)
            .padding(.horizontal, DooreSize.smallGap)
            .frame(minHeight: DooreSize.fieldHeight)
            .background(DooreColor.well, in: RoundedRectangle(cornerRadius: DooreSize.fieldRadius))
            .overlay {
                RoundedRectangle(cornerRadius: DooreSize.fieldRadius)
                    .strokeBorder(DooreColor.line, lineWidth: DooreSize.hairline)
            }
            .frame(minHeight: DooreSize.tapTarget)
    }
}

private struct Hover: ViewModifier {
    @State private var hovering = false
    func body(content: Content) -> some View {
        #if os(macOS)
        content.brightness(hovering ? 0.035 : 0).onHover { hovering = $0 }
        #else
        content
        #endif
    }
}

extension View {
    func doorePanel() -> some View { modifier(Panel()) }
    func dooreField() -> some View { modifier(FieldAppearance()) }
    func dooreFont(_ size: CGFloat, weight: Font.Weight = .regular) -> some View {
        modifier(DooreFont(size: size, weight: weight))
    }
    func dooreHover() -> some View { modifier(Hover()) }
}
