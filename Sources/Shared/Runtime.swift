import Cocoa
import SwiftUI
import Carbon

final class GlobalShortcut {
    private var reference: EventHotKeyRef?
    private var handler: EventHandlerRef?
    var action: (() -> Void)?

    init() {
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return noErr }
            Unmanaged<GlobalShortcut>.fromOpaque(context).takeUnretainedValue().action?()
            return noErr
        }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }

    func register(key: String, preset: Int) -> Bool {
        if let reference { UnregisterEventHotKey(reference); self.reference = nil }
        let codes: [String: Int] = ["F": kVK_ANSI_F, "O": kVK_ANSI_O, "G": kVK_ANSI_G, "N": kVK_ANSI_N, "R": kVK_ANSI_R]
        let modifiers = [cmdKey | shiftKey, controlKey | optionKey, controlKey | optionKey | cmdKey]
        let id = EventHotKeyID(signature: 0x4D544F4C, id: 1)
        return RegisterEventHotKey(UInt32(codes[key] ?? kVK_ANSI_F), UInt32(modifiers[max(0, min(preset, 2))]), id,
                                  GetApplicationEventTarget(), 0, &reference) == noErr
    }

    deinit {
        if let reference { UnregisterEventHotKey(reference) }
        if let handler { RemoveEventHandler(handler) }
    }
}

final class ToolHost: NSObject {
    let preferences: ToolPreferences
    private let root: AnyView
    private var item: NSStatusItem?
    private let popover = NSPopover()
    private var panel: NSPanel?
    private var panelSizeObservation: NSKeyValueObservation?
    private let shortcut = GlobalShortcut()
    private var registeredPreset: Int?
    var beforeOpen: (() -> Void)?
    var shortcutAction: (() -> Void)?

    init<Content: View>(_ preferences: ToolPreferences, @ViewBuilder content: () -> Content) {
        self.preferences = preferences
        root = AnyView(content())
        super.init()
    }

    func start() {
        if RunMode.dark { NSApp.appearance = NSAppearance(named: .darkAqua) }
        if RunMode.light { NSApp.appearance = NSAppearance(named: .aqua) }
        if let path = RunMode.screenshot { render(to: path); return }
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item?.button?.target = self
        item?.button?.action = #selector(clicked)
        item?.button?.setAccessibilityLabel(preferences.identity.name)
        item?.button?.toolTip = preferences.identity.name
        let controller = NSHostingController(rootView: root)
        controller.sizingOptions = .preferredContentSize
        popover.contentViewController = controller
        popover.behavior = .transient
        popover.animates = false
        shortcut.action = { [weak self] in
            guard let self else { return }
            if let action = self.shortcutAction { action() } else { self.toggle() }
        }
        preferences.onChange = { [weak self] in self?.updatePreferences() }
        updatePreferences()
        setStatus(symbol: preferences.identity.symbol)
        // A persistent utility window is useful for UI inspection without a transient popover.
        if CommandLine.arguments.contains("--show") {
            DispatchQueue.main.async { self.beforeOpen?(); self.showPanel() }
        }
    }

    func updatePreferences() {
        guard item != nil else { return }
        if registeredPreset != preferences.shortcut {
            let success = shortcut.register(key: preferences.identity.key, preset: preferences.shortcut)
            registeredPreset = preferences.shortcut
            preferences.shortcutRegistered = success
            if !success {
                preferences.error = "Dieses Tastenkürzel ist bereits belegt. Wähle in den Einstellungen ein anderes."
            } else if preferences.error?.hasPrefix("Dieses Tastenkürzel") == true { preferences.error = nil }
        }
        item?.isVisible = preferences.showIcon || !preferences.shortcutRegistered
    }

    func setStatus(symbol: String?, text: String = "", fixedWidth: CGFloat? = nil, tooltip: String? = nil) {
        guard let item, let button = item.button else { return }
        let image = symbol.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: preferences.identity.name) }?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 13, weight: .regular))
        image?.isTemplate = true
        button.image = image
        button.imagePosition = .imageLeading
        button.attributedTitle = NSAttributedString(string: text, attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)])
        item.length = fixedWidth ?? NSStatusItem.variableLength
        button.toolTip = tooltip ?? preferences.identity.name
    }

    @objc private func clicked() { toggle() }

    func toggle() {
        if popover.isShown { popover.performClose(nil); return }
        if panel?.isVisible == true { panel?.orderOut(nil); return }
        beforeOpen?()
        preferences.refreshLogin()
        if let item, item.isVisible, let button = item.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
            popover.contentViewController?.view.window?.makeKey()
        } else { showPanel() }
    }

    func dismiss() { popover.performClose(nil); panel?.orderOut(nil) }

    func reopen() {
        if !popover.isShown && panel?.isVisible != true { toggle() }
    }

    private func showPanel() {
        if panel == nil {
            let controller = NSHostingController(rootView: root)
            controller.sizingOptions = .preferredContentSize
            let window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: ToolStyle.width, height: 500),
                                 styleMask: [.titled, .closable, .utilityWindow], backing: .buffered, defer: false)
            window.title = preferences.identity.name
            window.contentViewController = controller
            window.setContentSize(controller.view.fittingSize)
            window.isReleasedWhenClosed = false
            window.level = .floating
            window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            panel = window
            panelSizeObservation = controller.observe(\.preferredContentSize, options: [.new]) { [weak window] _, change in
                guard let window, let size = change.newValue, size.width > 0, size.height > 0 else { return }
                let top = window.frame.maxY
                window.setContentSize(size)
                window.setFrameOrigin(NSPoint(x: window.frame.minX, y: top - window.frame.height))
            }
        }
        panel?.center()
        NSApp.activate(ignoringOtherApps: true)
        panel?.makeKeyAndOrderFront(nil)
    }

    private func render(to path: String) {
        let controller = NSHostingController(rootView: root.environment(\.controlActiveState, .key))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: ToolStyle.width, height: 800),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentViewController = controller
        let size = controller.view.fittingSize
        window.setContentSize(NSSize(width: ToolStyle.width, height: size.height))
        window.orderFront(nil)
        // SwiftUI's first layout and symbol loading finish on the main run loop.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            controller.view.layoutSubtreeIfNeeded()
            let view = controller.view
            guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { exit(2) }
            view.cacheDisplay(in: view.bounds, to: bitmap)
            guard let data = bitmap.representation(using: .png, properties: [:]) else { exit(2) }
            do { try data.write(to: URL(fileURLWithPath: path)) }
            catch { fputs("Screenshot: \(error)\n", stderr); exit(2) }
            exit(0)
        }
    }
}
