import Foundation
import CoreGraphics

struct BadgeValue: Equatable {
    let count: Int
    let isLowerBound: Bool
    let hasActivity: Bool

    var label: String? {
        if count > 0 { return "\(count)\(isLowerBound ? "+" : "")" }
        return hasActivity ? "•" : nil
    }

    static func parse(_ input: String?) -> BadgeValue {
        let text = input?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else { return BadgeValue(count: 0, isLowerBound: false, hasActivity: false) }
        // Only numeric badge labels are counts. A status such as “Sync 2” is activity.
        let numeric = text.hasSuffix("+") ? String(text.dropLast()) : text
        if !numeric.isEmpty, numeric.allSatisfy({ $0.isASCII && $0.isNumber }), let number = Int(numeric) {
            return BadgeValue(count: number, isLowerBound: text.hasSuffix("+") && number > 0, hasActivity: false)
        }
        return BadgeValue(count: 0, isLowerBound: false, hasActivity: true)
    }
}

enum SpeedFormat {
    static func string(_ bytesPerSecond: Double, bits: Bool = false) -> String {
        var value = (bytesPerSecond.isFinite ? max(0, bytesPerSecond) : 0) * (bits ? 8 : 1)
        let units = bits ? ["bit/s", "kbit/s", "Mbit/s", "Gbit/s"] : ["B/s", "kB/s", "MB/s", "GB/s"]
        var index = 0
        while value >= 1000, index < units.count - 1 { value /= 1000; index += 1 }
        // Round before selecting precision, so 999.99 kB/s becomes 1.0 MB/s.
        if value >= 999.5, index < units.count - 1 { value /= 1000; index += 1 }
        let format = value < 10 && index > 0 ? "%.1f" : "%.0f"
        return "\(String(format: format, locale: Locale(identifier: "de_AT"), value)) \(units[index])"
    }
}

struct TrafficCounter: Equatable {
    let received: UInt64
    let sent: UInt64
}

struct TrafficSampler {
    private var previous: [String: TrafficCounter] = [:]
    private var previousTime: TimeInterval?

    mutating func reset() { previous = [:]; previousTime = nil }

    mutating func sample(_ current: [String: TrafficCounter], at time: TimeInterval) -> (down: Double, up: Double) {
        defer { previous = current; previousTime = time }
        guard let lastTime = previousTime else { return (0, 0) }
        let elapsed = time - lastTime
        // A missed interval or wake establishes a new baseline, rather than a misleading spike.
        guard elapsed > 0, elapsed <= 5 else { return (0, 0) }
        var down = 0.0, up = 0.0
        for (name, counter) in current {
            guard let old = previous[name] else { continue }
            if counter.received >= old.received { down += Double(counter.received - old.received) }
            if counter.sent >= old.sent { up += Double(counter.sent - old.sent) }
        }
        return (down / elapsed, up / elapsed)
    }
}

struct GridLayout: Identifiable, Equatable {
    let id: String
    let name: String
    let cells: [CGRect]

    static let all: [GridLayout] = [
        GridLayout(id: "halves", name: "Zwei Hälften", cells: [
            CGRect(x: 0, y: 0, width: 0.5, height: 1), CGRect(x: 0.5, y: 0, width: 0.5, height: 1)]),
        GridLayout(id: "wide", name: "Groß & klein", cells: [
            CGRect(x: 0, y: 0, width: 2.0/3, height: 1), CGRect(x: 2.0/3, y: 0, width: 1.0/3, height: 1)]),
        GridLayout(id: "thirds", name: "Drei Spalten", cells: (0..<3).map {
            CGRect(x: Double($0)/3, y: 0, width: 1.0/3, height: 1) }),
        GridLayout(id: "stack", name: "Eins & zwei", cells: [
            CGRect(x: 0, y: 0, width: 2.0/3, height: 1),
            CGRect(x: 2.0/3, y: 0, width: 1.0/3, height: 0.5),
            CGRect(x: 2.0/3, y: 0.5, width: 1.0/3, height: 0.5)]),
        GridLayout(id: "quarters", name: "Vier Felder", cells: (0..<4).map {
            CGRect(x: Double($0 % 2)/2, y: Double($0 / 2)/2, width: 0.5, height: 0.5) }),
        GridLayout(id: "single", name: "Ein Fenster", cells: [CGRect(x: 0, y: 0, width: 1, height: 1)])
    ]

    /// Coordinates use a top-left origin, matching the macOS accessibility API.
    func frames(in screen: CGRect, gap: Double) -> [CGRect] {
        let inset = max(0, min(gap, min(screen.width, screen.height) / 20))
        let usable = screen.insetBy(dx: inset / 2, dy: inset / 2)
        return cells.map { cell in
            // Round shared edges consistently; CGRect.integral expands adjacent thirds into each other.
            let left = (usable.minX + cell.minX * usable.width + inset / 2).rounded()
            let top = (usable.minY + cell.minY * usable.height + inset / 2).rounded()
            let right = (usable.minX + cell.maxX * usable.width - inset / 2).rounded()
            let bottom = (usable.minY + cell.maxY * usable.height - inset / 2).rounded()
            return CGRect(x: left, y: top, width: max(1, right - left), height: max(1, bottom - top))
        }
    }
}
