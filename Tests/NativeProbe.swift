import Cocoa
import ApplicationServices

final class ProbeDelegate: NSObject, NSApplicationDelegate {
    private var fixtures: [NSWindow] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.dockTile.badgeLabel = "99+"
        let screen = NSScreen.screens[0]
        for index in 0..<3 {
            let window = NSWindow(contentRect: NSRect(x: screen.visibleFrame.minX + 50 + CGFloat(index) * 35,
                                                       y: screen.visibleFrame.minY + 80 + CGFloat(index) * 35,
                                                       width: 260, height: 200),
                                  styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            window.title = "Grid Test \(index + 1)"
            window.isReleasedWhenClosed = false; window.makeKeyAndOrderFront(nil)
            fixtures.append(window)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            let visible = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
            let frame = screen.visibleFrame
            let targetScreen = CGRect(x: frame.minX, y: CGDisplayBounds(CGMainDisplayID()).height - frame.maxY, width: frame.width, height: frame.height)
            DispatchQueue.global(qos: .userInitiated).async {
                var failed = false
                let badge = BadgeReader().read(pid: getpid())
                if badge.readable && badge.label == "99+" { print("PASS · Read own Dock badge by PID (99+)") }
                else { print("FAIL · Own Dock badge: readable=\(badge.readable), label=\(badge.label ?? "nil")"); failed = true }
                if WindowAccess.trusted {
                    let windows = WindowAccess.read(applications: [(pid: getpid(), name: "Grid Native Test", icon: NSImage())], visible: visible)
                    if windows.count != 3 { print("FAIL · Expected three own windows, found \(windows.count)"); failed = true }
                    let targets = GridLayout.all.first { $0.id == "thirds" }!.frames(in: targetScreen, gap: 12)
                    var originals: [(AXUIElement, CGRect)] = []
                    var placed = 0
                    for (index, window) in windows.prefix(3).enumerated() {
                        guard let element = window.element, let old = WindowAccess.frame(element) else { failed = true; continue }
                        originals.append((element, old))
                        if WindowAccess.move(element, to: targets[index]) { placed += 1 }
                    }
                    let restored = originals.filter { WindowAccess.move($0.0, to: $0.1) }.count
                    if placed == 3 && restored == 3 { print("PASS · Positioned and restored three own native windows") }
                    else { print("FAIL · Placed \(placed)/3; restored \(restored)/3"); failed = true }
                } else { print("SKIP · Window movement: no existing Accessibility permission. No permission was requested.") }
                let status: Int32 = failed ? 1 : 0
                DispatchQueue.main.async {
                    self.fixtures.forEach { $0.close() }
                    exit(status)
                }
            }
        }
    }
}

@main struct NativeProbe {
    static func main() {
        let app = NSApplication.shared
        let delegate = ProbeDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }
}
