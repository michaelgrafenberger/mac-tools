import Cocoa
import SwiftUI
import ServiceManagement

enum ToolStyle {
    static let width: CGFloat = 372
    static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((hex >> 16) & 255)/255,
                           green: CGFloat((hex >> 8) & 255)/255,
                           blue: CGFloat(hex & 255)/255, alpha: 1)
        })
    }
    static let canvas = adaptive(0xF5F4F0, 0x202320)
    static let surface = adaptive(0xFCFBF8, 0x292D29)
    static let ink = adaptive(0x252C28, 0xEEF0E9)
    static let secondary = adaptive(0x72796F, 0xA7AEA3)
    static let line = adaptive(0xDFE2D9, 0x3D443B)
    static let accent = adaptive(0x526B59, 0xB0C8A7)
    static let accentInk = adaptive(0xFFFFFF, 0x202A20)
    static let tint = adaptive(0xE5EADD, 0x354330)
    static let warning = adaptive(0x93622D, 0xDDB57A)
}

struct ToolIdentity {
    let name: String
    let tagline: String
    let symbol: String
    let key: String
    let defaultShortcut: Int

    static let fokus = ToolIdentity(name: "Fokus", tagline: "Raum für das Wesentliche.", symbol: "circle.inset.filled", key: "F", defaultShortcut: 0)
    static let offen = ToolIdentity(name: "Offen", tagline: "Alles im Blick. Kopf frei.", symbol: "tray", key: "O", defaultShortcut: 1)
    static let grid = ToolIdentity(name: "Grid", tagline: "Ein Platz für jedes Fenster.", symbol: "rectangle.split.2x2", key: "G", defaultShortcut: 1)
    static let netSpeed = ToolIdentity(name: "NetSpeed", tagline: "Dein Netzwerk. Auf einen Blick.", symbol: "arrow.down", key: "N", defaultShortcut: 1)
    static let ramUsage = ToolIdentity(name: "RAM", tagline: "Mehr Überblick. Weniger Ballast.", symbol: "memorychip", key: "R", defaultShortcut: 1)
}

enum RunMode {
    static let preview = CommandLine.arguments.contains("--preview")
    static var screenshot: String? {
        guard let index = CommandLine.arguments.firstIndex(of: "--screenshot"), index + 1 < CommandLine.arguments.count else { return nil }
        return CommandLine.arguments[index + 1]
    }
    static let dark = CommandLine.arguments.contains("--dark")
    static let light = CommandLine.arguments.contains("--light")
}

final class ToolPreferences: ObservableObject {
    let identity: ToolIdentity
    private let defaults: UserDefaults
    var onChange: (() -> Void)?
    @Published var error: String?
    @Published var showIcon: Bool { didSet { save(showIcon, "showIcon") } }
    @Published var shortcut: Int { didSet { save(shortcut, "shortcut") } }
    @Published private(set) var loginEnabled = false
    @Published private(set) var loginNeedsApproval = false
    @Published var shortcutRegistered = true

    init(_ identity: ToolIdentity) {
        self.identity = identity
        defaults = RunMode.preview ? UserDefaults(suiteName: "at.grafenberger.tools.preview.\(getpid())")! : .standard
        showIcon = defaults.object(forKey: "showIcon") as? Bool ?? true
        shortcut = defaults.object(forKey: "shortcut") as? Int ?? identity.defaultShortcut
        refreshLogin()
    }

    private func save(_ value: Any, _ key: String) {
        defaults.set(value, forKey: key)
        onChange?()
    }

    var shortcutLabel: String { ["⌘ ⇧", "⌃ ⌥", "⌃ ⌥ ⌘"][max(0, min(shortcut, 2))] + " " + identity.key }

    func refreshLogin() {
        guard !RunMode.preview else { return }
        loginEnabled = SMAppService.mainApp.status == .enabled || SMAppService.mainApp.status == .requiresApproval
        loginNeedsApproval = SMAppService.mainApp.status == .requiresApproval
    }

    func setLogin(_ enabled: Bool) {
        guard !RunMode.preview else { return }
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            error = nil
        } catch { self.error = "Autostart konnte nicht geändert werden: \(error.localizedDescription)" }
        refreshLogin()
    }
}

struct ToolScaffold<Content: View>: View {
    @ObservedObject var preferences: ToolPreferences
    let status: String
    var isActive = false
    let content: Content
    @State private var settingsVisible = CommandLine.arguments.contains("--settings")

    init(_ preferences: ToolPreferences, status: String, isActive: Bool = false, @ViewBuilder content: () -> Content) {
        self.preferences = preferences
        self.status = status
        self.isActive = isActive
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            header
            if settingsVisible { settings } else { content }
            if let error = preferences.error { InlineNotice(text: error, warning: true) }
            footer
        }
        .padding(24)
        .frame(width: ToolStyle.width)
        .foregroundStyle(ToolStyle.ink)
        .background(ToolStyle.canvas)
        .tint(ToolStyle.accent)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack {
                Spacer()
                if RunMode.preview {
                    Text("VORSCHAU").font(.system(size: 8, weight: .semibold)).tracking(1)
                        .foregroundStyle(ToolStyle.secondary)
                } else {
                    HStack(spacing: 5) {
                        Circle().fill(isActive ? ToolStyle.accent : ToolStyle.secondary.opacity(0.6)).frame(width: 5, height: 5)
                        Text(status).font(.system(size: 10, weight: .medium))
                    }.foregroundStyle(ToolStyle.secondary)
                }
            }
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(preferences.identity.name).font(.system(size: 29, weight: .medium)).tracking(-1)
                    Text(preferences.identity.tagline).font(.system(size: 12)).foregroundStyle(ToolStyle.secondary)
                }
                Spacer(minLength: 12)
                Image(systemName: preferences.identity.symbol)
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(ToolStyle.accent)
                    .frame(width: 46, height: 46)
                    .background(Circle().fill(ToolStyle.tint))
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 13) {
            Rectangle().fill(ToolStyle.line).frame(height: 1)
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "keyboard").font(.system(size: 10))
                    Text(preferences.shortcutLabel).font(.system(size: 10, weight: .medium, design: .monospaced))
                }
                .foregroundStyle(ToolStyle.secondary)
                .help("Mit diesem Tastenkürzel erreichst du die App auch ohne Menübar-Icon.")
                Spacer()
                Button { withAnimation(.easeInOut(duration: 0.15)) { settingsVisible.toggle() } } label: {
                    Image(systemName: settingsVisible ? "xmark" : "slider.horizontal.3")
                        .font(.system(size: 12, weight: .medium)).frame(width: 25, height: 22)
                }
                .buttonStyle(.plain).foregroundStyle(ToolStyle.secondary)
                .help(settingsVisible ? "Einstellungen schließen" : "Einstellungen")
                .accessibilityLabel(settingsVisible ? "Einstellungen schließen" : "Einstellungen")
                Menu {
                    Button("\(preferences.identity.name) beenden") { NSApp.terminate(nil) }
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 12)).frame(width: 20, height: 22)
                }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    .foregroundStyle(ToolStyle.secondary).accessibilityLabel("Weitere Aktionen")
            }
        }
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionCaption("Einstellungen")
            SettingRow("Icon in der Menübar", isOn: $preferences.showIcon)
                .disabled(!preferences.shortcutRegistered && preferences.showIcon)
            SettingRow("Bei Anmeldung starten", isOn: Binding(get: { preferences.loginEnabled }, set: preferences.setLogin))
                .disabled(RunMode.preview)
            HStack {
                Text("Tastenkürzel").font(.system(size: 12, weight: .medium))
                Spacer()
                Picker("Tastenkürzel", selection: $preferences.shortcut) {
                    Text("⌘ ⇧ \(preferences.identity.key)").tag(0)
                    Text("⌃ ⌥ \(preferences.identity.key)").tag(1)
                    Text("⌃ ⌥ ⌘ \(preferences.identity.key)").tag(2)
                }.labelsHidden().frame(width: 124).disabled(RunMode.preview)
            }
            if preferences.loginNeedsApproval {
                Text("Autostart bitte in den Systemeinstellungen unter Anmeldeobjekte erlauben.")
                    .font(.system(size: 11)).foregroundStyle(ToolStyle.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Text("Ohne Icon: Tastenkürzel nutzen oder die App erneut öffnen.")
                .font(.system(size: 11)).foregroundStyle(ToolStyle.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: 12)).toggleStyle(.switch).controlSize(.small)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(15).background(RoundedRectangle(cornerRadius: 13).fill(ToolStyle.surface))
    }
}

struct SectionCaption: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased()).font(.system(size: 9, weight: .semibold)).tracking(1.5).foregroundStyle(ToolStyle.secondary)
    }
}

struct Surface<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        content.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 15, style: .continuous).fill(ToolStyle.surface))
            .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(ToolStyle.line.opacity(0.7), lineWidth: 0.7))
    }
}

struct ToolButton: ButtonStyle {
    var primary = true
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12, weight: .medium))
            .frame(maxWidth: .infinity).padding(.vertical, 12)
            .foregroundStyle(primary ? ToolStyle.accentInk : ToolStyle.ink)
            .background(RoundedRectangle(cornerRadius: 10).fill(primary ? ToolStyle.accent : ToolStyle.tint))
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

struct InlineNotice: View {
    let text: String
    var warning = false
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: warning ? "exclamationmark.circle" : "info.circle").padding(.top, 1)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: 11)).foregroundStyle(warning ? ToolStyle.warning : ToolStyle.secondary)
    }
}

struct SettingRow: View {
    let title: String
    let subtitle: String?
    @Binding var isOn: Bool
    init(_ title: String, subtitle: String? = nil, isOn: Binding<Bool>) {
        self.title = title; self.subtitle = subtitle; self._isOn = isOn
    }
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 12, weight: .medium))
                if let subtitle { Text(subtitle).font(.system(size: 10)).foregroundStyle(ToolStyle.secondary) }
            }.frame(maxWidth: .infinity, alignment: .leading)
            Toggle(title, isOn: $isOn).labelsHidden().toggleStyle(.switch).controlSize(.small)
                .accessibilityLabel(title)
        }
    }
}
