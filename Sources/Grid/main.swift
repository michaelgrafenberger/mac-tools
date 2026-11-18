import Cocoa
import SwiftUI
import UniformTypeIdentifiers

final class GridModel: ObservableObject {
    @Published private(set) var trusted = RunMode.preview || WindowAccess.trusted
    @Published private(set) var windows: [ManagedWindow] = []
    @Published private(set) var refreshing = false
    @Published private(set) var working = false
    @Published private(set) var canUndo = false
    @Published var layoutID: String {
        didSet {
            assignments = [:]; selectedCell = 0
            if !RunMode.preview { UserDefaults.standard.set(layoutID, forKey: "layout") }
        }
    }
    @Published var assignments: [Int: String] = [:]
    @Published var selectedCell = 0
    @Published var gap: Double {
        didSet { if !RunMode.preview { UserDefaults.standard.set(gap, forKey: "gap") } }
    }
    @Published var screenID: UInt32 = 0
    @Published var notice: String?
    @Published var warning = false
    var onApplied: (() -> Void)?
    private var undoFrames: [(AXUIElement, CGRect)] = []
    private let queue = DispatchQueue(label: "tools.grid.windows", qos: .userInitiated)
    var layout: GridLayout { GridLayout.all.first { $0.id == layoutID } ?? GridLayout.all[0] }
    var screens: [NSScreen] { NSScreen.screens }
    var selectedScreen: NSScreen? { screens.first { self.id($0) == screenID } ?? screens.first }
    func id(_ screen: NSScreen) -> UInt32 { (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0 }

    init() {
        layoutID = RunMode.preview ? "stack" : (UserDefaults.standard.string(forKey: "layout") ?? "halves")
        gap = UserDefaults.standard.object(forKey: "gap") as? Double ?? 12
        screenID = NSScreen.main.map(id) ?? 0
        if RunMode.preview {
            let fixtures = [("Safari", "Kampagnenübersicht", "safari"), ("Figma", "Entwurf · Social", "square.on.circle"), ("Mail", "Kundenfeedback", "envelope")]
            windows = fixtures.enumerated().map { index, fixture in
                ManagedWindow(id: "preview-\(index)", owner: fixture.0, title: fixture.1,
                              icon: NSImage(systemSymbolName: fixture.2, accessibilityDescription: nil)!, pid: 0,
                              element: nil, frame: .zero, order: index)
            }
            assignments = [0: "preview-0", 1: "preview-1", 2: "preview-2"]
        }
    }

    func refresh() {
        guard !RunMode.preview, !refreshing, !working else { return }
        trusted = WindowAccess.trusted
        guard trusted else { windows = []; assignments = [:]; return }
        refreshing = true
        let applications = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && !$0.isHidden && $0.processIdentifier != getpid()
        }.map { (pid: $0.processIdentifier, name: $0.localizedName ?? "App", icon: $0.icon ?? NSImage()) }
        let visible = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }) { screenID = id(screen) }
        queue.async {
            let found = WindowAccess.read(applications: applications, visible: visible)
            DispatchQueue.main.async {
                self.windows = found; self.refreshing = false
                let valid = Set(found.map(\.id))
                self.assignments = self.assignments.filter { valid.contains($0.value) }
            }
        }
    }

    func assign(_ id: String, to cell: Int? = nil) {
        guard windows.contains(where: { $0.id == id }), !working else { return }
        let target = cell ?? selectedCell
        guard layout.cells.indices.contains(target) else { return }
        assignments = assignments.filter { $0.value != id }
        assignments[target] = id
        selectedCell = layout.cells.indices.first(where: { assignments[$0] == nil }) ?? target
        notice = nil
    }

    func autoFill() {
        assignments = [:]
        for (index, window) in windows.prefix(layout.cells.count).enumerated() { assignments[index] = window.id }
        notice = nil
    }

    func apply() {
        guard !RunMode.preview, !working, trusted, let screen = selectedScreen else { return }
        let primaryHeight = CGDisplayBounds(CGMainDisplayID()).height
        let visible = screen.visibleFrame
        let axFrame = CGRect(x: visible.minX, y: primaryHeight - visible.maxY, width: visible.width, height: visible.height)
        let targets = layout.frames(in: axFrame, gap: gap)
        let jobs: [(ManagedWindow, CGRect)] = assignments.sorted { $0.key < $1.key }.compactMap { cell, windowID in
            guard targets.indices.contains(cell), let window = windows.first(where: { $0.id == windowID }) else { return nil }
            return (window, targets[cell])
        }
        guard !jobs.isEmpty else { return }
        working = true; notice = nil
        queue.async {
            var undo: [(AXUIElement, CGRect)] = []
            var successes = 0
            for (window, target) in jobs {
                guard let element = window.element, let original = WindowAccess.frame(element) else { continue }
                // Capture before attempting: an application may move even when its size is constrained.
                undo.append((element, original))
                if WindowAccess.move(element, to: target) { successes += 1 }
            }
            let snapshots = undo, count = successes
            DispatchQueue.main.async {
                self.undoFrames = snapshots; self.canUndo = !snapshots.isEmpty; self.working = false
                self.warning = count < jobs.count
                self.notice = count == jobs.count ? "\(count) \(count == 1 ? "Fenster angeordnet." : "Fenster angeordnet.")" :
                    "\(count) von \(jobs.count) Fenstern exakt angeordnet. Manche Apps begrenzen Größe oder Position. Du kannst die Änderung rückgängig machen."
                if count == jobs.count { self.onApplied?() }
            }
        }
    }

    func undo() {
        guard !RunMode.preview, !working, canUndo else { return }
        working = true
        let previous = undoFrames
        queue.async {
            let restored = previous.filter { WindowAccess.move($0.0, to: $0.1) }.count
            DispatchQueue.main.async {
                self.working = false
                self.warning = restored != previous.count
                self.notice = restored == previous.count ? "Vorherige Anordnung wiederhergestellt." : "Nicht alle Fenster konnten wiederhergestellt werden. Möglicherweise wurde ein Fenster geschlossen."
                self.canUndo = false; self.undoFrames = []
            }
        }
    }
}

struct LayoutThumbnail: View {
    let layout: GridLayout
    let selected: Bool
    var body: some View {
        GeometryReader { geometry in
            ForEach(Array(layout.cells.enumerated()), id: \.offset) { _, cell in
                RoundedRectangle(cornerRadius: 2)
                    .fill(selected ? ToolStyle.accent.opacity(0.7) : ToolStyle.secondary.opacity(0.28))
                    .frame(width: max(1, cell.width * geometry.size.width - 3), height: max(1, cell.height * geometry.size.height - 3))
                    .position(x: cell.midX * geometry.size.width, y: cell.midY * geometry.size.height)
            }
        }.frame(height: 25).padding(9)
            .background(RoundedRectangle(cornerRadius: 8).fill(selected ? ToolStyle.tint : ToolStyle.surface))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(selected ? ToolStyle.accent.opacity(0.5) : ToolStyle.line, lineWidth: 0.7))
    }
}

struct GridCell: View {
    @ObservedObject var model: GridModel
    let index: Int
    @State private var targeted = false
    private var window: ManagedWindow? { model.windows.first { $0.id == model.assignments[index] } }
    var body: some View {
        Button { model.selectedCell = index } label: {
            VStack(spacing: 5) {
                if let window {
                    Image(nsImage: window.icon).resizable().scaledToFit().frame(width: 21, height: 21).foregroundStyle(ToolStyle.accent)
                    Text(window.owner).font(.system(size: 10, weight: .medium)).lineLimit(1)
                } else {
                    Image(systemName: "plus").font(.system(size: 13, weight: .light))
                    Text("Fenster \(index + 1)").font(.system(size: 9)).lineLimit(1)
                }
            }
            .foregroundStyle(window == nil ? ToolStyle.secondary : ToolStyle.ink)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 8).fill(window != nil || targeted ? ToolStyle.tint : ToolStyle.surface))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(model.selectedCell == index || targeted ? ToolStyle.accent.opacity(0.75) : ToolStyle.line,
                                                            style: StrokeStyle(lineWidth: model.selectedCell == index ? 1.1 : 0.7, dash: window == nil ? [3, 3] : [])))
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
            .accessibilityLabel("Feld \(index + 1): \(window?.owner ?? "leer")")
            .contextMenu { if window != nil { Button("Zuordnung entfernen") { model.assignments.removeValue(forKey: index) } } }
            .onDrop(of: [UTType.utf8PlainText], isTargeted: $targeted) { providers in
                guard let provider = providers.first else { return false }
                provider.loadItem(forTypeIdentifier: UTType.utf8PlainText.identifier, options: nil) { item, _ in
                    let value = (item as? String) ?? (item as? Data).flatMap { String(data: $0, encoding: .utf8) }
                    if let value { DispatchQueue.main.async { model.assign(value, to: index) } }
                }
                return true
            }
    }
}

struct GridView: View {
    @ObservedObject var model: GridModel
    @ObservedObject var preferences: ToolPreferences

    var body: some View {
        ToolScaffold(preferences, status: model.trusted ? "Bereit" : "Einrichten", isActive: model.trusted) {
            if !model.trusted {
                permission
            } else {
                workspace
            }
        }
    }

    private var permission: some View {
        VStack(alignment: .leading, spacing: 18) {
            Surface {
                VStack(alignment: .leading, spacing: 14) {
                    Image(systemName: "rectangle.and.hand.point.up.left").font(.system(size: 27, weight: .light)).foregroundStyle(ToolStyle.accent)
                    Text("Einmal erlauben. Dann aufräumen.").font(.system(size: 16, weight: .medium)).tracking(-0.3)
                    Text("Grid benötigt die Bedienungshilfen-Freigabe, um deine Fenster zu verschieben und ihre Größe zu ändern.")
                        .font(.system(size: 12)).foregroundStyle(ToolStyle.secondary).fixedSize(horizontal: false, vertical: true)
                    Button("Bedienungshilfen erlauben") { WindowAccess.requestPermission() }.buttonStyle(ToolButton())
                    Button("Freigabe erneut prüfen") { model.refresh() }.buttonStyle(.plain)
                        .font(.system(size: 11)).foregroundStyle(ToolStyle.accent)
                }
            }
            InlineNotice(text: "Fenstertitel und Positionen bleiben auf deinem Mac. Grid benötigt keine Bildschirmaufnahmen.")
        }
    }

    private var workspace: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                SectionCaption("01 · Layout wählen")
                HStack(spacing: 5) {
                    ForEach(GridLayout.all) { layout in
                        Button { model.layoutID = layout.id } label: { LayoutThumbnail(layout: layout, selected: model.layoutID == layout.id) }
                            .buttonStyle(.plain).help(layout.name).accessibilityLabel(layout.name)
                            .accessibilityAddTraits(model.layoutID == layout.id ? .isSelected : [])
                    }
                }
                GeometryReader { geometry in
                    ForEach(Array(model.layout.cells.enumerated()), id: \.offset) { index, cell in
                        GridCell(model: model, index: index)
                            .frame(width: max(1, cell.width * geometry.size.width - 5), height: max(1, cell.height * geometry.size.height - 5))
                            .position(x: cell.midX * geometry.size.width, y: cell.midY * geometry.size.height)
                    }
                }.frame(height: 142).padding(9)
                    .background(RoundedRectangle(cornerRadius: 12).fill(ToolStyle.line.opacity(0.25)))
                HStack {
                    Text(model.layout.name).font(.system(size: 10)).foregroundStyle(ToolStyle.secondary)
                    Spacer()
                    Menu {
                        Button("Ohne Abstand") { model.gap = 0 }
                        Button("12 pt Abstand") { model.gap = 12 }
                        Button("20 pt Abstand") { model.gap = 20 }
                    } label: { Text("\(Int(model.gap)) pt Abstand").font(.system(size: 10)) }
                        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().foregroundStyle(ToolStyle.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    SectionCaption("02 · Fenster zuordnen")
                    Spacer()
                    Button { model.refresh() } label: { Image(systemName: "arrow.clockwise").font(.system(size: 10)) }
                        .buttonStyle(.plain).disabled(model.refreshing || model.working || RunMode.preview)
                        .foregroundStyle(ToolStyle.secondary).accessibilityLabel("Fenster aktualisieren")
                }
                if model.windows.isEmpty {
                    Text(model.refreshing ? "Fenster werden gesucht …" : "Keine anordnungsfähigen Fenster auf diesem Schreibtisch.")
                        .font(.system(size: 11)).foregroundStyle(ToolStyle.secondary).padding(.vertical, 12)
                } else {
                    ScrollView {
                        VStack(spacing: 3) {
                            ForEach(model.windows) { window in
                                Button { model.assign(window.id) } label: {
                                    HStack(spacing: 9) {
                                        Image(nsImage: window.icon).resizable().scaledToFit().frame(width: 22, height: 22).foregroundStyle(ToolStyle.accent)
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(window.owner).font(.system(size: 11, weight: .medium))
                                            Text(window.title).font(.system(size: 10)).foregroundStyle(ToolStyle.secondary).lineLimit(1)
                                        }
                                        Spacer(minLength: 5)
                                        if let slot = model.assignments.first(where: { $0.value == window.id })?.key {
                                            Text("\(slot + 1)").font(.system(size: 10, design: .monospaced)).foregroundStyle(ToolStyle.accent)
                                                .frame(width: 21, height: 21).background(Circle().fill(ToolStyle.tint))
                                        } else { Image(systemName: "plus").font(.system(size: 10)).foregroundStyle(ToolStyle.secondary) }
                                    }.padding(.vertical, 5).contentShape(Rectangle())
                                }.buttonStyle(.plain).disabled(model.working)
                                    .onDrag { NSItemProvider(object: window.id as NSString) }
                                    .accessibilityLabel("\(window.owner), \(window.title), Feld \(model.selectedCell + 1) zuweisen")
                            }
                        }
                    }.frame(height: min(CGFloat(model.windows.count) * 44, 132))
                }
                HStack {
                    Text("Feld wählen, dann Fenster anklicken.").font(.system(size: 9)).foregroundStyle(ToolStyle.secondary)
                    Spacer(minLength: 3)
                    Button("Auto") { model.autoFill() }.font(.system(size: 10, weight: .medium)).buttonStyle(.plain)
                        .foregroundStyle(ToolStyle.accent).disabled(model.windows.isEmpty || model.working)
                        .help("Zuletzt verwendete Fenster der Reihe nach zuordnen")
                }
            }
            if model.screens.count > 1 {
                Picker("Bildschirm", selection: $model.screenID) {
                    ForEach(model.screens, id: \.self) { screen in Text(screen.localizedName).tag(model.id(screen)) }
                }.font(.system(size: 11)).controlSize(.small)
            }
            VStack(spacing: 10) {
                Button { model.apply() } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "rectangle.split.2x2")
                        Text(model.working ? "Einen Moment …" : "Fenster anordnen")
                    }
                }.buttonStyle(ToolButton()).disabled(model.assignments.isEmpty || model.working || RunMode.preview)
                if model.canUndo {
                    Button("Letzte Anordnung rückgängig machen") { model.undo() }
                        .buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(ToolStyle.accent).disabled(model.working)
                }
            }
            if let notice = model.notice { InlineNotice(text: notice, warning: model.warning) }
        }.disabled(model.working)
    }
}

final class GridDelegate: NSObject, NSApplicationDelegate {
    private let model = GridModel()
    private let preferences = ToolPreferences(.grid)
    private var host: ToolHost!
    func applicationDidFinishLaunching(_ notification: Notification) {
        host = ToolHost(preferences) { GridView(model: model, preferences: preferences) }
        host.beforeOpen = { [weak self] in self?.model.refresh() }
        model.onApplied = { [weak self] in self?.host.dismiss() }
        host.start()
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { host?.reopen(); return true }
}

let app = NSApplication.shared
let delegate = GridDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
