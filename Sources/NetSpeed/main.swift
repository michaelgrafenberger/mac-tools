import Cocoa
import SwiftUI

struct TrafficPoint: Identifiable {
    let id = UUID()
    let down: Double
    let up: Double
}

final class NetworkModel: ObservableObject {
    @Published private(set) var down = 0.0
    @Published private(set) var up = 0.0
    @Published private(set) var history: [TrafficPoint] = []
    @Published private(set) var interfaces: [String] = []
    @Published private(set) var available = true
    @Published var useBits: Bool { didSet { save(useBits, "useBits"); onChange?() } }
    @Published var menuMode: Int { didSet { save(menuMode, "menuMode"); onChange?() } }
    @Published var selectedInterface: String {
        didSet { save(selectedInterface, "interface"); sampler.reset(); history = []; tick() }
    }
    private var sampler = TrafficSampler()
    private var timer: Timer?
    private var wakeObserver: NSObjectProtocol?
    var onChange: (() -> Void)?

    init() {
        let d = UserDefaults.standard
        useBits = d.bool(forKey: "useBits")
        menuMode = d.object(forKey: "menuMode") as? Int ?? 1
        selectedInterface = d.string(forKey: "interface") ?? "all"
        if RunMode.preview {
            down = 2_400_000; up = 184_000; interfaces = ["en0"]
            history = (0..<60).map { i in
                let phase = Double(i)
                return TrafficPoint(down: max(0, 2_000_000 + sin(phase / 5) * 1_000_000 + sin(phase * 1.4) * 300_000),
                                    up: max(0, 240_000 + sin(phase / 4) * 160_000))
            }
        }
    }

    private func save(_ value: Any, _ key: String) { if !RunMode.preview { UserDefaults.standard.set(value, forKey: key) } }

    func start() {
        guard !RunMode.preview else { return }
        tick()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common); self.timer = timer
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.sampler.reset(); self?.history = []; self?.tick()
        }
    }

    func tick() {
        guard !RunMode.preview else { return }
        guard let counters = NetworkReader.read() else {
            available = false; down = 0; up = 0; sampler.reset(); onChange?(); return
        }
        available = true
        interfaces = counters.keys.sorted()
        let selected = selectedInterface == "all" ? counters : counters.filter { $0.key == selectedInterface }
        let sample = sampler.sample(selected, at: ProcessInfo.processInfo.systemUptime)
        down = sample.down; up = sample.up
        history.append(TrafficPoint(down: down, up: up))
        if history.count > 60 { history.removeFirst(history.count - 60) }
        onChange?()
    }
}

struct TrafficChart: View {
    let points: [TrafficPoint]
    var body: some View {
        Canvas { context, size in
            for fraction in [0.0, 0.5, 1.0] {
                var line = Path()
                let y = 4 + (size.height - 8) * fraction
                line.move(to: CGPoint(x: 0, y: y)); line.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(line, with: .color(ToolStyle.line), style: StrokeStyle(lineWidth: 0.6, dash: [2, 4]))
            }
            guard points.count > 1 else { return }
            let maximum = max(points.map { max($0.down, $0.up) }.max() ?? 1, 1000) * 1.15
            func path(_ upload: Bool) -> Path {
                var path = Path()
                for (index, point) in points.enumerated() {
                    let x = size.width * CGFloat(index) / CGFloat(points.count - 1)
                    let y = size.height - 4 - (size.height - 8) * (upload ? point.up : point.down) / maximum
                    if index == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
                }
                return path
            }
            let download = path(false)
            var fill = download
            fill.addLine(to: CGPoint(x: size.width, y: size.height)); fill.addLine(to: CGPoint(x: 0, y: size.height)); fill.closeSubpath()
            context.fill(fill, with: .linearGradient(Gradient(colors: [ToolStyle.accent.opacity(0.13), ToolStyle.accent.opacity(0.01)]),
                                                    startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
            context.stroke(download, with: .color(ToolStyle.accent), style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
            context.stroke(path(true), with: .color(ToolStyle.secondary.opacity(0.7)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
        }.frame(height: 86).accessibilityLabel("Netzwerkverlauf der letzten \(points.count) Sekunden")
    }
}

struct NetworkView: View {
    @ObservedObject var model: NetworkModel
    @ObservedObject var preferences: ToolPreferences
    var body: some View {
        ToolScaffold(preferences, status: model.available ? "Live" : "Nicht verfügbar", isActive: model.available) {
            Surface {
                VStack(spacing: 21) {
                    HStack(alignment: .top, spacing: 10) {
                        metric("Download", symbol: "arrow.down", value: model.down)
                        Rectangle().fill(ToolStyle.line).frame(width: 1, height: 46)
                        metric("Upload", symbol: "arrow.up", value: model.up)
                    }
                    TrafficChart(points: model.history)
                    HStack {
                        Text("−\(max(model.history.count, 1)) s")
                        Spacer()
                        HStack(spacing: 5) { Circle().fill(ToolStyle.accent).frame(width: 4, height: 4); Text("Jetzt") }
                    }.font(.system(size: 9, design: .monospaced)).foregroundStyle(ToolStyle.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 14) {
                SectionCaption("So viel Überblick wie du willst")
                Picker("Menübar", selection: $model.menuMode) {
                    Text("Nur Icon").tag(0)
                    Text("Download").tag(1)
                    Text("Beide").tag(2)
                }.pickerStyle(.segmented).labelsHidden().controlSize(.small)
                    .frame(maxWidth: .infinity).accessibilityLabel("Anzeige in der Menübar")
                HStack {
                    Text("Einheit").font(.system(size: 12))
                    Spacer()
                    Picker("Einheit", selection: $model.useBits) {
                        Text("Byte/s").tag(false); Text("Bit/s").tag(true)
                    }.labelsHidden().pickerStyle(.segmented).controlSize(.small).frame(width: 156)
                }
                Picker("Schnittstelle", selection: $model.selectedInterface) {
                    Text("Alle aktiven").tag("all")
                    ForEach(model.interfaces, id: \.self) { Text($0).tag($0) }
                    if model.selectedInterface != "all", !model.interfaces.contains(model.selectedInterface) {
                        Text("\(model.selectedInterface) · inaktiv").tag(model.selectedInterface)
                    }
                }.font(.system(size: 12)).controlSize(.small)
            }
            InlineNotice(text: "Zeigt den aktuellen Netzwerkverkehr einschließlich lokaler Übertragungen. Kein Geschwindigkeitstest.")
            if !model.available { InlineNotice(text: "Die Netzwerkzähler sind gerade nicht verfügbar.", warning: true) }
            if model.interfaces.isEmpty && model.available { InlineNotice(text: "Keine aktive unterstützte Netzwerkschnittstelle gefunden.") }
        }
    }

    private func metric(_ title: String, symbol: String, value: Double) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 5) { Image(systemName: symbol); Text(title) }
                .font(.system(size: 10)).foregroundStyle(ToolStyle.secondary)
            let pieces = SpeedFormat.string(value, bits: model.useBits).split(separator: " ")
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(model.available ? String(pieces.first ?? "0") : "—")
                    .font(.system(size: 30, weight: .light)).tracking(-1).monospacedDigit()
                Text(String(pieces.last ?? "B/s")).font(.system(size: 10)).foregroundStyle(ToolStyle.secondary)
            }.lineLimit(1).minimumScaleFactor(0.6)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

final class NetSpeedDelegate: NSObject, NSApplicationDelegate {
    private let model = NetworkModel()
    private let preferences = ToolPreferences(.netSpeed)
    private var host: ToolHost!
    func applicationDidFinishLaunching(_ notification: Notification) {
        host = ToolHost(preferences) { NetworkView(model: model, preferences: preferences) }
        model.onChange = { [weak self] in self?.updateStatus() }
        host.start(); model.start(); updateStatus()
    }
    private func updateStatus() {
        let down = SpeedFormat.string(model.down, bits: model.useBits)
        let up = SpeedFormat.string(model.up, bits: model.useBits)
        let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        let template = model.menuMode == 2 ? "↓ 888 Gbit/s  ↑ 888 Gbit/s" : "↓ 888 Gbit/s"
        let width = ceil((template as NSString).size(withAttributes: [.font: font]).width) + 16
        let text = model.available ? (model.menuMode == 2 ? "↓ \(down)  ↑ \(up)" : "↓ \(down)") : "—"
        host.setStatus(symbol: model.menuMode == 0 ? "arrow.down" : nil,
                       text: model.menuMode == 0 ? "" : text, fixedWidth: model.menuMode == 0 ? nil : width,
                       tooltip: "NetSpeed · ↓ \(down) · ↑ \(up)")
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { host?.reopen(); return true }
}

let app = NSApplication.shared
let delegate = NetSpeedDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
