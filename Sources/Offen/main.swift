import Cocoa
import SwiftUI

struct BadgeApp: Identifiable {
    let id: String
    let name: String
    let bundleID: String
    let pid: pid_t
    let icon: NSImage
    let badge: BadgeValue
    let readable: Bool
    var hasActivity: Bool { badge.count > 0 || badge.hasActivity }
    var status: String {
        if !readable { return "Badge nicht verfügbar" }
        if badge.count > 0 { return "\(badge.label ?? "") im Dock-Badge" }
        return badge.hasActivity ? "Neue Aktivität" : "Kein Badge"
    }
}

final class InboxModel: ObservableObject {
    @Published private(set) var apps: [BadgeApp] = []
    @Published private(set) var lastUpdate: Date?
    @Published private(set) var refreshing = false
    @Published private(set) var failedCount = 0
    @Published var notice: String?
    var onChange: (() -> Void)?
    private let reader = BadgeReader()
    private let queue = DispatchQueue(label: "tools.offen.badges", qos: .utility)
    private let pinned: Set<String> = ["com.tinyspeck.slackmacgap", "com.apple.mail", "com.microsoft.Outlook", "com.readdle.smartemail-Mac"]
    private let ignored: Set<String> = ["com.apple.systempreferences", "com.apple.AppStore"]
    private var hidden: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: "hidden") ?? []) }
        set { if !RunMode.preview { UserDefaults.standard.set(Array(newValue), forKey: "hidden") } }
    }
    var hiddenCount: Int { hidden.count }
    var total: Int { apps.reduce(0) { sum, app in let result = sum.addingReportingOverflow(app.badge.count); return result.overflow ? Int.max : result.partialValue } }
    var lowerBound: Bool { apps.contains { $0.badge.isLowerBound } || total == Int.max }
    var totalLabel: String { "\(total)\(lowerBound ? "+" : "")" }
    var activityCount: Int { apps.filter(\.hasActivity).count }
    var status: String { failedCount > 0 ? "Teilweise verfügbar" : (activityCount > 0 ? "Aktivität" : "Ruhig") }

    init() {
        if RunMode.preview {
            func icon(_ symbol: String) -> NSImage { NSImage(systemSymbolName: symbol, accessibilityDescription: nil)! }
            apps = [
                BadgeApp(id: "mail", name: "Mail", bundleID: "", pid: 0, icon: icon("envelope.fill"), badge: .parse("8"), readable: true),
                BadgeApp(id: "slack", name: "Slack", bundleID: "", pid: 0, icon: icon("number"), badge: .parse("3"), readable: true),
                BadgeApp(id: "outlook", name: "Outlook", bundleID: "", pid: 0, icon: icon("tray.fill"), badge: .parse(nil), readable: true)
            ]
            lastUpdate = Date()
        }
    }

    func refresh() {
        guard !RunMode.preview, !refreshing else { return }
        refreshing = true
        let skipped = ignored.union(hidden)
        let candidates = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.processIdentifier != getpid() &&
            !skipped.contains($0.bundleIdentifier ?? "") &&
            !($0.localizedName ?? "").localizedCaseInsensitiveContains("ClickUp")
        }.map { (pid: $0.processIdentifier, name: $0.localizedName ?? "App", bid: $0.bundleIdentifier ?? "pid.\($0.processIdentifier)", icon: $0.icon ?? NSImage()) }
        queue.async { [weak self] in
            guard let self else { return }
            var results: [BadgeApp] = [], failures = 0
            for candidate in candidates {
                let result = self.reader.read(pid: candidate.pid)
                if !result.readable { failures += 1 }
                let badge = BadgeValue.parse(result.label)
                guard badge.count > 0 || badge.hasActivity || self.pinned.contains(candidate.bid) else { continue }
                results.append(BadgeApp(id: "\(candidate.bid)#\(candidate.pid)", name: candidate.name, bundleID: candidate.bid,
                                        pid: candidate.pid, icon: candidate.icon, badge: badge, readable: result.readable))
            }
            results.sort {
                if $0.badge.count != $1.badge.count { return $0.badge.count > $1.badge.count }
                if $0.badge.hasActivity != $1.badge.hasActivity { return $0.badge.hasActivity }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            let sorted = results, failed = failures
            DispatchQueue.main.async {
                self.apps = sorted; self.failedCount = failed; self.lastUpdate = Date(); self.refreshing = false
                self.onChange?()
            }
        }
    }

    func hide(_ app: BadgeApp) {
        guard !RunMode.preview else { return }
        hidden.insert(app.bundleID); apps.removeAll { $0.bundleID == app.bundleID }; onChange?()
    }
    func resetHidden() { hidden = []; refresh() }
}

struct BadgeRow: View {
    let app: BadgeApp
    let action: () -> Void
    @State private var hovered = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(nsImage: app.icon).resizable().scaledToFit().frame(width: 27, height: 27)
                    .foregroundStyle(ToolStyle.accent)
                    .frame(width: 35, height: 35)
                VStack(alignment: .leading, spacing: 4) {
                    Text(app.name).font(.system(size: 12, weight: .medium))
                    Text(app.status).font(.system(size: 10)).foregroundStyle(ToolStyle.secondary)
                }
                Spacer()
                if let label = app.badge.label {
                    Text(label).font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(ToolStyle.accent).padding(.horizontal, 9).padding(.vertical, 6)
                        .background(Capsule().fill(ToolStyle.tint))
                } else {
                    Image(systemName: app.readable ? "checkmark" : "minus")
                        .font(.system(size: 10)).foregroundStyle(ToolStyle.secondary)
                }
            }
            .padding(.vertical, 9).padding(.horizontal, 10)
            .contentShape(Rectangle())
            .background(RoundedRectangle(cornerRadius: 10).fill(hovered ? ToolStyle.tint.opacity(0.5) : .clear))
        }.buttonStyle(.plain).onHover { hovered = $0 }
            .accessibilityLabel("\(app.name), \(app.status), öffnen")
    }
}

struct InboxView: View {
    @ObservedObject var model: InboxModel
    @ObservedObject var preferences: ToolPreferences
    let open: (BadgeApp) -> Void

    var body: some View {
        ToolScaffold(preferences, status: model.status, isActive: model.activityCount > 0) {
            Surface {
                HStack(alignment: .center, spacing: 15) {
                    Text(model.totalLabel).font(.system(size: 48, weight: .light, design: .rounded)).tracking(-2).monospacedDigit()
                        .foregroundStyle(ToolStyle.accent)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Im Dock-Badge").font(.system(size: 13, weight: .medium))
                        Text(model.failedCount > 0 ? "Nicht alle Badges sind lesbar." :
                                (model.activityCount == 0 ? "Gerade keine neue Aktivität." : "Aktivität in \(model.activityCount) \(model.activityCount == 1 ? "App" : "Apps")."))
                            .font(.system(size: 11)).foregroundStyle(ToolStyle.secondary)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    SectionCaption("Deine Apps")
                    Spacer()
                    Button { model.refresh() } label: { Image(systemName: "arrow.clockwise").font(.system(size: 10)) }
                        .buttonStyle(.plain).foregroundStyle(ToolStyle.secondary).disabled(model.refreshing || RunMode.preview)
                        .accessibilityLabel("Badges aktualisieren")
                }
                if model.apps.isEmpty {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(model.refreshing ? "Ein kurzer Blick ins Dock …" : "Hier ist gerade Platz.")
                            .font(.system(size: 14, weight: .medium))
                        Text(model.failedCount > 0 ? "Dock-Badges konnten nicht vollständig gelesen werden." : "Laufende Mail-Apps und Apps mit Badge erscheinen hier.")
                            .font(.system(size: 11)).foregroundStyle(ToolStyle.secondary)
                    }.padding(.vertical, 18)
                } else {
                    ScrollView {
                        VStack(spacing: 1) {
                            ForEach(model.apps) { app in
                                BadgeRow(app: app) { open(app) }
                                    .contextMenu { Button("\(app.name) ausblenden") { model.hide(app) } }
                            }
                        }
                    }.frame(height: min(CGFloat(model.apps.count) * 58, 290))
                }
                if model.hiddenCount > 0 {
                    Button("\(model.hiddenCount) ausgeblendete Apps wieder anzeigen") { model.resetHidden() }
                        .buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(ToolStyle.accent)
                }
            }
            InlineNotice(text: "Spiegelt Dock-Badges laufender Apps. Zahlen und Punkte werden von der jeweiligen App bestimmt.")
            if model.failedCount > 0 {
                InlineNotice(text: "\(model.failedCount) \(model.failedCount == 1 ? "App liefert" : "Apps liefern") derzeit keine lesbaren Badge-Daten.", warning: true)
            }
            if let notice = model.notice { InlineNotice(text: notice, warning: true) }
        }
    }
}

final class OffenDelegate: NSObject, NSApplicationDelegate {
    private let model = InboxModel()
    private let preferences = ToolPreferences(.offen)
    private var host: ToolHost!
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        host = ToolHost(preferences) { InboxView(model: model, preferences: preferences) { [weak self] item in
            guard let self, !RunMode.preview else { return }
            guard let app = NSRunningApplication(processIdentifier: item.pid), !app.isTerminated else {
                self.model.notice = "Die App wurde inzwischen beendet."; self.model.refresh(); return
            }
            self.host.dismiss()
            if !app.activate(options: [.activateAllWindows]) { self.model.notice = "Die App konnte nicht geöffnet werden." }
        } }
        host.beforeOpen = { [weak self] in self?.model.refresh() }
        model.onChange = { [weak self] in self?.updateStatus() }
        host.start(); updateStatus(); model.refresh()
        guard !RunMode.preview else { return }
        let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in self?.model.refresh() }
        RunLoop.main.add(timer, forMode: .common); self.timer = timer
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.model.refresh() })
        }
    }

    private func updateStatus() {
        let text = model.total > 0 ? " \(model.totalLabel)" : (model.activityCount > 0 ? " •" : (model.failedCount > 0 ? " ?" : ""))
        host.setStatus(symbol: model.activityCount > 0 ? "tray.full" : "tray", text: text,
                       tooltip: "Offen · \(model.totalLabel) im Dock-Badge\(model.failedCount > 0 ? " · Teilweise verfügbar" : "")")
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { host?.reopen(); return true }
}

let app = NSApplication.shared
let delegate = OffenDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
