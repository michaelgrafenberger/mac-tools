import Cocoa
import SwiftUI

final class RAMModel: ObservableObject {
    @Published private(set) var memory: MemorySnapshot?
    @Published private(set) var processes: [MemoryProcess] = []
    @Published private(set) var refreshing = false
    @Published var selectedID: String?
    @Published var showDetails = false
    @Published var notice: String?
    @Published var displayMode: Int {
        didSet { if !RunMode.preview { UserDefaults.standard.set(displayMode, forKey: "displayMode") }; onChange?() }
    }
    var onChange: (() -> Void)?
    private let monitor = MemoryMonitor()
    private let scanner = ProcessScanner()
    private let queue = DispatchQueue(label: "tools.ram.measurement", qos: .utility)
    private var timer: Timer?
    private var shouldScan = false

    init() {
        displayMode = UserDefaults.standard.object(forKey: "displayMode") as? Int ?? 1
        if RunMode.preview {
            let gb: UInt64 = 1_073_741_824
            memory = MemorySnapshot(total: 24 * gb, app: 12 * gb, wired: 3 * gb, compressed: 2 * gb, cached: 4 * gb, swapUsed: gb / 2, pressure: 1)
            processes = [("Browser", "globe", 39, 5.4), ("Design", "square.on.circle", 13, 3.2), ("Mail", "envelope", 4, 1.1), ("Musik", "music.note", 8, 0.8)].enumerated().map { index, fixture in
                MemoryProcess(id: "preview-\(index)", name: fixture.0, appPath: nil,
                              members: (0..<fixture.2).map { ProcessIdentity(pid: Int32($0), user: 0, startedSeconds: 0, startedMicros: 0) },
                              bytes: UInt64(fixture.3 * Double(gb)), icon: NSImage(systemSymbolName: fixture.1, accessibilityDescription: nil)!)
            }
        }
    }
    func start() {
        guard !RunMode.preview else { return }
        tick()
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common); self.timer = timer
    }
    func open() { shouldScan = true; tick() }
    func tick() {
        guard !RunMode.preview, !refreshing else { return }
        refreshing = true
        let scan = shouldScan
        shouldScan = false
        queue.async {
            let memory = self.monitor.sample()
            let processes = scan ? self.scanner.top() : nil
            DispatchQueue.main.async {
                self.memory = memory
                if let processes { self.processes = processes }
                self.refreshing = false; self.onChange?()
            }
        }
    }

    func end(_ entry: MemoryProcess, force: Bool) {
        guard !RunMode.preview else { return }
        let current = entry.members.filter { $0.user == getuid() && $0.pid != getpid() && $0.isCurrent }
        guard !current.isEmpty else { notice = "Dieser Eintrag wurde inzwischen beendet oder geändert."; tick(); return }
        if let path = entry.appPath {
            let apps = NSWorkspace.shared.runningApplications.filter { app in
                app.bundleURL?.resolvingSymlinksInPath().path == path && current.contains(where: { $0.pid == app.processIdentifier })
            }
            if !apps.isEmpty {
                var accepted = 0
                for app in apps {
                    // Re-check immediately before asking macOS to terminate this exact instance.
                    guard current.contains(where: { $0.pid == app.processIdentifier && $0.isCurrent }) else { continue }
                    if force ? app.forceTerminate() : app.terminate() { accepted += 1 }
                }
                notice = accepted > 0 ? (force ? "Sofortiges Beenden angefordert." : "Beenden angefordert. Die App kann noch nach dem Speichern fragen.") : "Die App konnte nicht beendet werden."
                selectedID = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.open() }
                return
            }
        }
        let accepted = current.filter { ProcessControl.signal($0, force: force) }.count
        notice = accepted > 0 ? "Beenden für \(accepted) \(accepted == 1 ? "Prozess" : "Prozesse") angefordert." : "Der Prozess konnte nicht beendet werden."
        selectedID = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.open() }
    }
}

struct RAMView: View {
    @ObservedObject var model: RAMModel
    @ObservedObject var preferences: ToolPreferences
    @State private var forceTarget: MemoryProcess?
    @State private var confirmForce = false

    var body: some View {
        ToolScaffold(preferences, status: model.memory?.pressureText ?? "Nicht verfügbar", isActive: model.memory?.pressure == 1) {
            if let memory = model.memory { summary(memory) }
            else { InlineNotice(text: "Speicherwerte sind gerade nicht verfügbar.", warning: true) }
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SectionCaption("Größte Apps & Prozesse")
                    Spacer()
                    Button { model.open() } label: { Image(systemName: "arrow.clockwise").font(.system(size: 10)) }
                        .buttonStyle(.plain).foregroundStyle(ToolStyle.secondary).disabled(model.refreshing || RunMode.preview)
                        .accessibilityLabel("Prozessliste aktualisieren")
                }
                if model.processes.isEmpty {
                    Text(model.refreshing ? "Speicher wird geprüft …" : "Keine lesbaren Prozesse verfügbar.")
                        .font(.system(size: 11)).foregroundStyle(ToolStyle.secondary).padding(.vertical, 12)
                } else {
                    ScrollView {
                        VStack(spacing: 3) { ForEach(model.processes) { entry in row(entry) } }
                    }.frame(height: min(CGFloat(model.processes.count) * 49 + (model.selectedID == nil ? 0 : 43), 245))
                }
                Text("Nach Speicherverbrauch sortiert · App-Helfer gebündelt")
                    .font(.system(size: 9)).foregroundStyle(ToolStyle.secondary)
            }
            if let memory = model.memory {
                VStack(alignment: .leading, spacing: 12) {
                    Button { withAnimation(.easeInOut(duration: 0.15)) { model.showDetails.toggle() } } label: {
                        HStack {
                            Text("Speicherdetails").font(.system(size: 11, weight: .medium))
                            Spacer()
                            Image(systemName: model.showDetails ? "chevron.up" : "chevron.down").font(.system(size: 9))
                        }
                    }.buttonStyle(.plain).foregroundStyle(ToolStyle.secondary)
                    if model.showDetails {
                        detail("App-Speicher", value: MemoryFormat.string(memory.app))
                        detail("Reserviert (Wired)", value: MemoryFormat.string(memory.wired))
                        detail("Komprimiert", value: MemoryFormat.string(memory.compressed))
                        detail("Cache", value: MemoryFormat.string(memory.cached))
                        detail("Swap", value: memory.swapUsed.map(MemoryFormat.string) ?? "Nicht verfügbar")
                        InlineNotice(text: "Die Auslastung allein zeigt keinen Engpass. Maßgeblich ist der Speicherdruck. App-Werte können gemeinsame Speicherbereiche enthalten und sind nicht zur Gesamtsumme addierbar.")
                    }
                }
            }
            HStack {
                Button("Aktivitätsanzeige öffnen") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))
                }.buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(ToolStyle.accent).disabled(RunMode.preview)
                Spacer()
                Picker("Menübar-Anzeige", selection: $model.displayMode) {
                    Text("Icon").tag(0); Text("%").tag(1); Text("GB").tag(2)
                }.labelsHidden().pickerStyle(.segmented).controlSize(.small).frame(width: 116)
            }
            if let notice = model.notice { InlineNotice(text: notice) }
        }
        .confirmationDialog("\(forceTarget?.name ?? "App") sofort beenden?", isPresented: $confirmForce, titleVisibility: .visible) {
            Button("Sofort beenden", role: .destructive) { if let target = forceTarget { model.end(target, force: true) }; forceTarget = nil }
            Button("Abbrechen", role: .cancel) { forceTarget = nil }
        } message: { Text("Ungespeicherte Änderungen können verloren gehen.") }
    }

    private func summary(_ memory: MemorySnapshot) -> some View {
        Surface {
            VStack(alignment: .leading, spacing: 15) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(MemoryFormat.gb(memory.used)).font(.system(size: 39, weight: .light)).tracking(-1.5).monospacedDigit()
                    Text("/ \(MemoryFormat.gb(memory.total)) GB").font(.system(size: 12)).foregroundStyle(ToolStyle.secondary)
                    Spacer()
                    Text("\(Int(memory.percent.rounded())) %").font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundStyle(ToolStyle.accent)
                }
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(ToolStyle.line)
                        Capsule().fill(memory.pressure == 4 || memory.pressure == 2 ? ToolStyle.warning : ToolStyle.accent)
                            .frame(width: geometry.size.width * min(1, max(0, memory.percent / 100)))
                    }
                }.frame(height: 4).accessibilityLabel("RAM zu \(Int(memory.percent.rounded())) Prozent belegt")
                HStack(spacing: 5) {
                    Circle().fill(memory.pressure == 1 ? ToolStyle.accent : ToolStyle.warning).frame(width: 5, height: 5)
                    Text("Speicherdruck: \(memory.pressureText.lowercased())").font(.system(size: 10)).foregroundStyle(ToolStyle.secondary)
                }
            }
        }
    }

    private func row(_ entry: MemoryProcess) -> some View {
        VStack(spacing: 8) {
            Button { withAnimation(.easeInOut(duration: 0.15)) { model.selectedID = model.selectedID == entry.id ? nil : entry.id } } label: {
                HStack(spacing: 10) {
                    Image(nsImage: entry.icon).resizable().scaledToFit().frame(width: 24, height: 24).foregroundStyle(ToolStyle.accent)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(entry.name).font(.system(size: 11, weight: .medium)).lineLimit(1)
                        Text(entry.count == 1 ? "1 Prozess" : "\(entry.count) Prozesse").font(.system(size: 9)).foregroundStyle(ToolStyle.secondary)
                    }
                    Spacer(minLength: 6)
                    Text(MemoryFormat.string(entry.bytes)).font(.system(size: 11, design: .monospaced)).foregroundStyle(ToolStyle.secondary)
                    Image(systemName: model.selectedID == entry.id ? "chevron.up" : "chevron.down").font(.system(size: 8)).foregroundStyle(ToolStyle.secondary)
                }.frame(height: 40).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("\(entry.name), \(MemoryFormat.string(entry.bytes)), Aktionen zeigen")
            if model.selectedID == entry.id {
                HStack {
                    Button("Beenden") { model.end(entry, force: false) }.buttonStyle(ToolButton(primary: false))
                    Button { forceTarget = entry; confirmForce = true } label: { Image(systemName: "xmark.octagon").frame(width: 24, height: 24) }
                        .buttonStyle(.plain).foregroundStyle(ToolStyle.warning).accessibilityLabel("\(entry.name) sofort beenden")
                        .help("Sofort beenden …")
                }.disabled(RunMode.preview)
            }
        }.padding(.horizontal, 7).padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 9).fill(model.selectedID == entry.id ? ToolStyle.tint.opacity(0.4) : .clear))
    }

    private func detail(_ title: String, value: String) -> some View {
        HStack { Text(title); Spacer(); Text(value).monospacedDigit() }.font(.system(size: 10)).foregroundStyle(ToolStyle.secondary)
    }
}

final class RAMDelegate: NSObject, NSApplicationDelegate {
    private let model = RAMModel()
    private let preferences = ToolPreferences(.ramUsage)
    private var host: ToolHost!
    func applicationDidFinishLaunching(_ notification: Notification) {
        host = ToolHost(preferences) { RAMView(model: model, preferences: preferences) }
        host.beforeOpen = { [weak self] in self?.model.open() }
        model.onChange = { [weak self] in self?.updateStatus() }
        host.start(); model.start(); updateStatus()
    }
    private func updateStatus() {
        let memory = model.memory
        var text = memory.map { "RAM \(Int($0.percent.rounded())) %" } ?? "RAM —"
        if model.displayMode == 2 { text = memory.map { "RAM \(MemoryFormat.gb($0.used)) GB" } ?? "RAM —" }
        let width: CGFloat = model.displayMode == 2 ? 118 : 84
        host.setStatus(symbol: model.displayMode == 0 ? "memorychip" : nil, text: model.displayMode == 0 ? "" : text,
                       fixedWidth: model.displayMode == 0 ? nil : width,
                       tooltip: memory.map { "RAM · \(MemoryFormat.string($0.used)) von \(MemoryFormat.string($0.total)) · Speicherdruck: \($0.pressureText)" } ?? "RAM · Nicht verfügbar")
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { host?.reopen(); return true }
}

let app = NSApplication.shared
let delegate = RAMDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
