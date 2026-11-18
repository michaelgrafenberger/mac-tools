import Foundation
import CoreGraphics

var checks = 0
func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    checks += 1
    if !condition() { fputs("FAIL: \(message)\n", stderr); exit(1) }
}
func close(_ value: Double, _ other: Double) -> Bool { abs(value - other) < 0.001 }

expect(BadgeValue.parse(nil).label == nil, "No label must not create activity")
expect(BadgeValue.parse("").hasActivity == false, "Empty badge")
expect(BadgeValue.parse("0").label == nil, "Zero is not new activity")
expect(BadgeValue.parse(" 12 ").count == 12, "Trim numeric badges")
expect(BadgeValue.parse("99+").label == "99+", "Preserve lower bounds")
expect(BadgeValue.parse("99+").isLowerBound, "Lower bound flag")
expect(BadgeValue.parse("•").hasActivity, "Activity dots")
expect(BadgeValue.parse("Sync 2").count == 0, "Do not invent counts from text")
expect(BadgeValue.parse("Sync 2").hasActivity, "Text badge is activity")
expect(BadgeValue.parse(String(repeating: "9", count: 60)).count == 0, "Overflowing labels must not crash")
expect(BadgeReader.label(in: #""StatusLabel"={ "label"="99+" }"#) == "99+", "Read a complete badge label")
expect(BadgeReader.label(in: #""StatusLabel"=NULL"#) == nil, "No badge in lsappinfo")
expect(BadgeReader.label(in: "\"label\" = \"•\"") == "•", "Whitespace and unicode badge output")
expect(SpeedFormat.string(0) == "0 B/s", "Idle speed")
expect(SpeedFormat.string(-1) == "0 B/s", "Negative sample")
expect(SpeedFormat.string(.nan) == "0 B/s", "Non-finite sample")
expect(SpeedFormat.string(1000) == "1,0 kB/s", "Decimal units")
expect(SpeedFormat.string(125_000, bits: true) == "1,0 Mbit/s", "Byte to bit conversion")
expect(SpeedFormat.string(999_990) == "1,0 MB/s", "Rounded unit boundary")
expect(SpeedFormat.string(2_400_000) == "2,4 MB/s", "German decimal formatting")

var sampler = TrafficSampler()
expect(close(sampler.sample(["en0": TrafficCounter(received: 100, sent: 50)], at: 10).down, 0), "First sample is a baseline")
let traffic = sampler.sample(["en0": TrafficCounter(received: 2100, sent: 1050)], at: 12)
expect(close(traffic.down, 1000) && close(traffic.up, 500), "Use elapsed time for rates")
let reset = sampler.sample(["en0": TrafficCounter(received: 1, sent: 1)], at: 13)
expect(reset.down == 0 && reset.up == 0, "Counter resets must not spike")
let join = sampler.sample(["en0": TrafficCounter(received: 101, sent: 51), "en5": TrafficCounter(received: UInt64.max, sent: 300)], at: 14)
expect(close(join.down, 100), "New interfaces establish a baseline")
expect(sampler.sample(["en0": TrafficCounter(received: 9_000_000, sent: 8_000_000)], at: 100).down == 0, "Wake or long gap must reset")
expect(sampler.sample(["en0": TrafficCounter(received: 9_000_100, sent: 8_000_100)], at: 100).down == 0, "Zero elapsed time")
sampler.reset()
expect(sampler.sample(["en0": TrafficCounter(received: 50, sent: 60)], at: 101).down == 0, "Explicit reset")
var largeSampler = TrafficSampler()
_ = largeSampler.sample(["en0": TrafficCounter(received: 4_294_967_000, sent: 0)], at: 0)
expect(close(largeSampler.sample(["en0": TrafficCounter(received: 4_394_967_000, sent: 0)], at: 1).down, 100_000_000), "Counters beyond UInt32.max")

let screens = [CGRect(x: 0, y: 25, width: 1440, height: 875),
               CGRect(x: -2560, y: -500, width: 2560, height: 1440),
               CGRect(x: 1440, y: -1080, width: 1080, height: 1920)]
for layout in GridLayout.all {
    for screen in screens {
        for gap in [0.0, 12, 20] {
            let frames = layout.frames(in: screen, gap: gap)
            expect(frames.count == layout.cells.count, "Layout preserves cell count")
            for (index, frame) in frames.enumerated() {
                expect(screen.contains(frame), "\(layout.id) fits on screen at \(screen.origin)")
                expect(frame.width > 0 && frame.height > 0, "Every assigned window has a positive size")
                for second in frames.indices where second > index {
                    expect(!frame.intersects(frames[second]), "\(layout.id) windows must not overlap")
                }
            }
        }
    }
}

if CommandLine.arguments.contains("--network") {
    guard let counters = NetworkReader.read() else { fputs("Network counters unavailable in this process.\n", stderr); exit(2) }
    expect(!counters.isEmpty, "A live supported interface is available")
    expect(counters.keys.allSatisfy { $0.hasPrefix("en") || $0.hasPrefix("pdp_ip") }, "Exclude virtual tunnel and loopback interfaces")
    print("Live kernel read: \(counters.count) supported interface(s).")
}
print("PASS · \(checks) checks")
