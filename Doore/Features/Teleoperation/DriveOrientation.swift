import SwiftUI

enum DriveLayout {
    @MainActor static var isPhone: Bool {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .phone
        #else
        false
        #endif
    }
}

extension View {
    @ViewBuilder func driveOrientation() -> some View {
        #if os(iOS)
        background(DriveOrientationAnchor().allowsHitTesting(false).accessibilityHidden(true))
        #else
        self
        #endif
    }
}

#if os(iOS)
import UIKit

@MainActor
final class DooreOrientationDelegate: NSObject, UIApplicationDelegate {
    private struct Lease {
        var holders: Set<UUID>
        let previous: UIInterfaceOrientation
    }
    private static var leases: [ObjectIdentifier: Lease] = [:]

    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        guard DriveLayout.isPhone else { return .all }
        if let scene = window?.windowScene, Self.leases[ObjectIdentifier(scene)] != nil { return .landscape }
        return .allButUpsideDown
    }

    fileprivate static func begin(_ token: UUID, window: UIWindow) {
        guard DriveLayout.isPhone, let scene = window.windowScene else { return }
        let id = ObjectIdentifier(scene)
        var lease = leases[id] ?? Lease(holders: [], previous: scene.interfaceOrientation)
        let first = lease.holders.isEmpty
        lease.holders.insert(token)
        leases[id] = lease
        if first {
            window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscape))
        }
    }

    fileprivate static func end(_ token: UUID, window: UIWindow) {
        guard let scene = window.windowScene else { return }
        let id = ObjectIdentifier(scene)
        guard var lease = leases[id], lease.holders.remove(token) != nil else { return }
        if !lease.holders.isEmpty { leases[id] = lease; return }
        leases.removeValue(forKey: id)
        window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        if lease.previous == .portrait { scene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait)) }
    }
}

private struct DriveOrientationAnchor: UIViewRepresentable {
    final class Anchor: UIView {
        let token = UUID()
        weak var registeredWindow: UIWindow?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard registeredWindow !== window else { return }
            if let registeredWindow { DooreOrientationDelegate.end(token, window: registeredWindow) }
            registeredWindow = window
            if let window { DooreOrientationDelegate.begin(token, window: window) }
        }
    }

    func makeUIView(context: Context) -> Anchor { Anchor() }
    func updateUIView(_ view: Anchor, context: Context) {}
    static func dismantleUIView(_ view: Anchor, coordinator: ()) {
        if let window = view.registeredWindow { DooreOrientationDelegate.end(view.token, window: window) }
        view.registeredWindow = nil
    }
}
#endif
