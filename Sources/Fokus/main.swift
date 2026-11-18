import Cocoa
import SwiftUI

// Optional enhancement. All styling falls back to public AppKit APIs if unavailable.
enum WindowBlur {
    private typealias Connection = @convention(c) () -> Int32
    private typealias SetRadius = @convention(c) (Int32, UInt32, Int32) -> Int32
    private static let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
    private static let connection: Connection? = {
        guard let handle, let symbol = dlsym(handle, "SLSMainConnectionID") else { return nil }
        return unsafeBitCast(symbol, to: Connection.self)
    }()
    private static let radius: SetRadius? = {
        guard let handle, let symbol = dlsym(handle, "SLSSetWindowBackgroundBlurRadius") else { return nil }
        return unsafeBitCast(symbol, to: SetRadius.self)
    }()
    static func apply(_ window: NSWindow, radius value: Double) -> Bool {
        guard let connection, let radius, window.windowNumber > 0 else { return false }
        return radius(connection(), UInt32(window.windowNumber), Int32(value)) == 0
    }
}

final class FocusOverlay {
    private var windows: [NSWindow] = []
    private var timer: Timer?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    var radius = 20.0 { didSet { style() } }
    var dim = 0.15 { didSet { style() } }
    private(set) var active = false

    func start() {
        guard !active else { return }
        active = true
        build()
        let timer = Timer(timeInterval: 0.15, repeats: true) { [weak self] _ in self?.track() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        let center = NotificationCenter.default
        let token = center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            self?.windows.forEach { $0.orderOut(nil) }; self?.build(); self?.track()
        }
        observers.append((center, token))
        track()
    }

    func stop() {
        active = false
        timer?.invalidate(); timer = nil
        observers.forEach { $0.0.removeObserver($0.1) }; observers = []
        windows.forEach { $0.orderOut(nil) }; windows = []
    }

    private func build() {
        windows = NSScreen.screens.map { screen in
            let window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.setFrame(screen.frame, display: false)
            window.isOpaque = false; window.hasShadow = false
            window.ignoresMouseEvents = true; window.isReleasedWhenClosed = false
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
            window.animationBehavior = .none
            return window
        }
        style()
    }

    private func style() {
        for window in windows {
            window.backgroundColor = NSColor.black.withAlphaComponent(max(dim, 0.02))
            if WindowBlur.apply(window, radius: radius) {
                window.contentView = nil
            } else {
                let effect = (window.contentView as? NSVisualEffectView) ?? NSVisualEffectView()
                effect.blendingMode = .behindWindow; effect.material = .fullScreenUI; effect.state = .active
                effect.alphaValue = min(radius / 40, 1)
                window.contentView = effect
            }
        }
    }

    private func track() {
        guard active, let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != getpid() else { return }
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return }
        let own = Set(windows.map(\.windowNumber))
        var target: Int?, next: Int?
        for info in list {
            guard info[kCGWindowLayer as String] as? Int == 0,
                  let number = info[kCGWindowNumber as String] as? Int else { continue }
            if target != nil { next = number; break }
            guard info[kCGWindowOwnerPID as String] as? Int == Int(app.processIdentifier),
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0.01,
                  let bounds = info[kCGWindowBounds as String] as? [String: Any],
                  let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary), frame.width > 80, frame.height > 60 else { continue }
            target = number
        }
        guard let target else { windows.forEach { $0.orderOut(nil) }; return }
        if next.map({ own.contains($0) }) != true {
            windows.forEach { $0.order(.below, relativeTo: target) }
        }
    }
}

final class FocusModel: ObservableObject {
    @Published private(set) var active = false
    @Published var radius: Double { didSet { store(radius, "blurRadius"); overlay.radius = radius } }
    @Published var dim: Double { didSet { store(dim, "dim"); overlay.dim = dim } }
    @Published var blurEnabled: Bool {
        didSet {
            store(blurEnabled, "blurEnabled")
            if active { blurEnabled ? overlay.start() : overlay.stop() }
        }
    }
    @Published var muteNotifications: Bool {
        didSet {
            store(muteNotifications, "muteNotifications")
            if active { runShortcut(muteNotifications ? "Fokus an" : "Fokus aus") }
        }
    }
    @Published var notice: String?
    var onChange: (() -> Void)?
    private let overlay = FocusOverlay()
    private let shortcutQueue = DispatchQueue(label: "tools.fokus.shortcuts")
    private var focusRequested = false
    private var shortcutGeneration = 0

    init() {
        let d = UserDefaults.standard
        radius = d.object(forKey: "blurRadius") as? Double ?? 20
        dim = d.object(forKey: "dim") as? Double ?? 0.15
        blurEnabled = d.object(forKey: "blurEnabled") as? Bool ?? true
        muteNotifications = d.object(forKey: "muteNotifications") as? Bool ?? false
        overlay.radius = radius; overlay.dim = dim
        if RunMode.preview { active = false; muteNotifications = false }
    }

    private func store(_ value: Any, _ key: String) { if !RunMode.preview { UserDefaults.standard.set(value, forKey: key) } }

    func toggle() {
        guard !RunMode.preview else { return }
        active.toggle()
        if active {
            if blurEnabled { overlay.start() }
            if muteNotifications { runShortcut("Fokus an") }
        } else {
            overlay.stop()
            if focusRequested { runShortcut("Fokus aus") }
        }
        onChange?()
    }

    func finish(_ completion: @escaping () -> Void) {
        overlay.stop(); active = false
        if focusRequested { runShortcut("Fokus aus", completion: completion) } else { completion() }
    }

    private func runShortcut(_ name: String, completion: (() -> Void)? = nil) {
        guard !RunMode.preview else { completion?(); return }
        if name == "Fokus an" { focusRequested = true }
        shortcutGeneration += 1
        let generation = shortcutGeneration
        shortcutQueue.async { [weak self] in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
            process.arguments = ["run", name]
            process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
            var succeeded = false
            do {
                try process.run()
                let deadline = ProcessInfo.processInfo.systemUptime + 8
                while process.isRunning && ProcessInfo.processInfo.systemUptime < deadline { Thread.sleep(forTimeInterval: 0.05) }
                if process.isRunning { process.terminate() } else { succeeded = process.terminationStatus == 0 }
            } catch { succeeded = false }
            let ok = succeeded
            DispatchQueue.main.async {
                if ok, name == "Fokus aus", self?.shortcutGeneration == generation { self?.focusRequested = false }
                self?.notice = ok ? nil : "„\(name)“ konnte nicht ausgeführt werden. Prüfe den Kurzbefehl in der Kurzbefehle-App."
                completion?()
            }
        }
    }
}

struct FocusStage: View {
    let active: Bool
    let blur: Double
    let dim: Double
    var body: some View {
        ZStack {
            Group {
                RoundedRectangle(cornerRadius: 8).fill(ToolStyle.tint).frame(width: 108, height: 65).offset(x: -62, y: -9)
                RoundedRectangle(cornerRadius: 8).fill(ToolStyle.line.opacity(0.8)).frame(width: 93, height: 68).offset(x: 67, y: 8)
            }.blur(radius: active ? blur / 9 : 0)
            if active { ToolStyle.ink.opacity(dim).clipShape(RoundedRectangle(cornerRadius: 10)) }
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 3) { ForEach(0..<3) { _ in Circle().fill(ToolStyle.secondary.opacity(0.35)).frame(width: 3, height: 3) } }
                Capsule().fill(ToolStyle.accent.opacity(0.6)).frame(width: 53, height: 4)
                Capsule().fill(ToolStyle.line).frame(width: 80, height: 3)
                Capsule().fill(ToolStyle.line).frame(width: 65, height: 3)
            }
            .padding(12).frame(width: 123, height: 82, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 9).fill(ToolStyle.surface)
                .shadow(color: .black.opacity(0.1), radius: 10, y: 5))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(ToolStyle.line, lineWidth: 1))
        }.frame(maxWidth: .infinity).frame(height: 110).clipped().accessibilityHidden(true)
    }
}

struct FocusView: View {
    @ObservedObject var model: FocusModel
    @ObservedObject var preferences: ToolPreferences
    let toggle: () -> Void

    var body: some View {
        ToolScaffold(preferences, status: model.active ? "Aktiv" : "Bereit", isActive: model.active) {
            Surface {
                VStack(alignment: .leading, spacing: 14) {
                    FocusStage(active: model.active, blur: model.radius, dim: model.dim)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(model.active ? "Ganz bei einer Sache." : "Ein bisschen weniger außenrum.")
                            .font(.system(size: 15, weight: .medium)).tracking(-0.3)
                        Text(model.active ? "Das aktive Fenster bleibt im Vordergrund." : "Andere Fenster treten in den Hintergrund.")
                            .font(.system(size: 11)).foregroundStyle(ToolStyle.secondary)
                    }
                    Button(action: toggle) {
                        HStack(spacing: 7) {
                            Image(systemName: model.active ? "pause" : "circle.inset.filled")
                            Text(model.active ? "Fokus beenden" : "Fokus starten")
                        }
                    }.buttonStyle(ToolButton()).disabled(RunMode.preview)
                }
            }
            VStack(alignment: .leading, spacing: 15) {
                SectionCaption("Dein Hintergrund")
                slider("Unschärfe", value: $model.radius, range: 0...60, valueText: "\(Int(model.radius))")
                    .disabled(!model.blurEnabled)
                slider("Abdunklung", value: $model.dim, range: 0...0.7, valueText: "\(Int((model.dim * 100).rounded())) %")
                    .disabled(!model.blurEnabled)
                SettingRow("Hintergrund beruhigen", isOn: $model.blurEnabled)
                SettingRow("Mitteilungen pausieren", subtitle: "Über deine macOS-Kurzbefehle", isOn: $model.muteNotifications)
                if model.muteNotifications {
                    InlineNotice(text: "Benötigt „Fokus an“ und „Fokus aus“ in Kurzbefehle. Beide müssen den gewünschten macOS-Fokus ein- bzw. ausschalten.")
                }
                if let notice = model.notice { InlineNotice(text: notice, warning: true) }
            }
        }
    }

    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, valueText: String) -> some View {
        VStack(spacing: 6) {
            HStack {
                Text(title).font(.system(size: 12))
                Spacer()
                Text(valueText).font(.system(size: 10, design: .monospaced)).foregroundStyle(ToolStyle.secondary)
            }
            Slider(value: value, in: range).controlSize(.small).accessibilityLabel(title)
        }
    }
}

final class FokusDelegate: NSObject, NSApplicationDelegate {
    private let model = FocusModel()
    private let preferences = ToolPreferences(.fokus)
    private var host: ToolHost!
    private var previousApp: NSRunningApplication?

    func applicationDidFinishLaunching(_ notification: Notification) {
        host = ToolHost(preferences) { FocusView(model: model, preferences: preferences, toggle: { [weak self] in
            guard let self else { return }
            self.host.dismiss()
            self.previousApp?.activate(options: [])
            self.model.toggle()
        }) }
        host.beforeOpen = { [weak self] in
            if let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != getpid() { self?.previousApp = app }
        }
        host.shortcutAction = { [weak self] in self?.model.toggle() }
        model.onChange = { [weak self] in self?.host.setStatus(symbol: self?.model.active == true ? "circle.inset.filled" : "circle") }
        host.start()
        host.setStatus(symbol: "circle")
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { host?.reopen(); return true }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        model.finish { DispatchQueue.main.async { sender.reply(toApplicationShouldTerminate: true) } }
        return .terminateLater
    }
}

let app = NSApplication.shared
let delegate = FokusDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
