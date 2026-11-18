import Cocoa
import ApplicationServices

struct ManagedWindow: Identifiable {
    let id: String
    let owner: String
    let title: String
    let icon: NSImage
    let pid: pid_t
    let element: AXUIElement?
    let frame: CGRect
    let order: Int
}

enum WindowAccess {
    static var trusted: Bool { AXIsProcessTrusted() }
    static func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    static func frame(_ element: AXUIElement) -> CGRect? {
        guard let position = attribute(element, kAXPositionAttribute), CFGetTypeID(position) == AXValueGetTypeID(),
              let size = attribute(element, kAXSizeAttribute), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero, dimensions = CGSize.zero
        guard AXValueGetValue(unsafeBitCast(position, to: AXValue.self), .cgPoint, &point),
              AXValueGetValue(unsafeBitCast(size, to: AXValue.self), .cgSize, &dimensions) else { return nil }
        return CGRect(origin: point, size: dimensions)
    }

    /// Called on the worker queue. No screen capture or window-image access is used.
    static func read(applications: [(pid: pid_t, name: String, icon: NSImage)], visible: [[String: Any]]) -> [ManagedWindow] {
        var result: [ManagedWindow] = []
        for candidate in applications {
            let onScreen = visible.enumerated().filter {
                $0.element[kCGWindowOwnerPID as String] as? Int == Int(candidate.pid) &&
                $0.element[kCGWindowLayer as String] as? Int == 0 &&
                ($0.element[kCGWindowAlpha as String] as? Double ?? 1) > 0.01
            }
            guard !onScreen.isEmpty else { continue }
            let application = AXUIElementCreateApplication(candidate.pid)
            AXUIElementSetMessagingTimeout(application, 0.3)
            guard let windows = attribute(application, kAXWindowsAttribute) as? [AXUIElement] else { continue }
            for element in windows {
                AXUIElementSetMessagingTimeout(element, 0.3)
                guard (attribute(element, kAXMinimizedAttribute) as? Bool) != true,
                      (attribute(element, "AXFullScreen") as? Bool) != true,
                      (attribute(element, kAXRoleAttribute) as? String) == kAXWindowRole,
                      let frame = frame(element), frame.width > 80, frame.height > 60 else { continue }
                // Match geometry as well as process, so windows on other Spaces are excluded.
                let match = onScreen.first { entry in
                    guard let bounds = entry.element[kCGWindowBounds as String] as? [String: Any],
                          let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { return false }
                    return abs(rect.minX - frame.minX) < 3 && abs(rect.minY - frame.minY) < 3 &&
                           abs(rect.width - frame.width) < 3 && abs(rect.height - frame.height) < 3
                }
                guard let match else { continue }
                var movable = DarwinBoolean(false), resizable = DarwinBoolean(false)
                guard AXUIElementIsAttributeSettable(element, kAXPositionAttribute as CFString, &movable) == .success,
                      AXUIElementIsAttributeSettable(element, kAXSizeAttribute as CFString, &resizable) == .success,
                      movable.boolValue, resizable.boolValue else { continue }
                let title = attribute(element, kAXTitleAttribute) as? String ?? ""
                result.append(ManagedWindow(id: "\(candidate.pid)-\(CFHash(element))", owner: candidate.name,
                                            title: title.isEmpty ? "Ohne Titel" : title, icon: candidate.icon,
                                            pid: candidate.pid, element: element, frame: frame, order: match.offset))
            }
        }
        return result.sorted { $0.order < $1.order }
    }

    /// Some applications enforce minimum sizes; verify the actual resulting geometry.
    static func move(_ element: AXUIElement, to target: CGRect) -> Bool {
        var point = target.origin, size = target.size
        guard let pointValue = AXValueCreate(.cgPoint, &point), let sizeValue = AXValueCreate(.cgSize, &size) else { return false }
        // Shrink before moving so a large original frame cannot force the new position on-screen.
        let first = AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, sizeValue)
        let second = AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, pointValue)
        let third = AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, sizeValue)
        guard first == .success, second == .success, third == .success, let actual = frame(element) else { return false }
        return abs(actual.minX - target.minX) <= 3 && abs(actual.minY - target.minY) <= 3 &&
               abs(actual.width - target.width) <= 3 && abs(actual.height - target.height) <= 3
    }
}
