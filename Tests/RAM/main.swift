import Cocoa
import Darwin

var checks = 0
func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    checks += 1
    guard condition() else { fputs("FAIL: \(message)\n", stderr); exit(1) }
}
let gb: UInt64 = 1_073_741_824
let snapshot = MemorySnapshot(total: 24 * gb, app: 12 * gb, wired: 3 * gb, compressed: 2 * gb, cached: 4 * gb, swapUsed: nil, pressure: nil)
expect(snapshot.used == 17 * gb, "Cache is not counted as used memory")
expect(abs(snapshot.percent - 70.8333333) < 0.001, "Memory percentage")
expect(snapshot.pressureText == "Nicht verfügbar", "Unavailable pressure must not be called normal")
expect(MemoryFormat.gb(gb) == "1,0", "German memory format")
expect(MemoryFormat.string(512 * 1_048_576) == "512 MB", "Megabyte values")
expect(MemoryFormat.string(2 * gb) == "2,0 GB", "Gigabyte values")
expect(MemorySnapshot(total: 0, app: 0, wired: 0, compressed: 0, cached: 0, swapUsed: nil, pressure: 1).percent == 0, "Zero physical memory")
expect(ProcessScanner.appBundle(in: "/Applications/Browser.app/Contents/Frameworks/Helper.app/Contents/MacOS/Helper") == "/Applications/Browser.app", "Group helpers under outermost app")
expect(ProcessScanner.appBundle(in: "/usr/bin/sleep") == nil, "Raw process is not an app")
expect(ProcessControl.protected.contains("WindowServer"), "Protect the window server")
expect(ProcessIdentity.read(0) == nil && ProcessIdentity.read(1) == nil, "Never accept PID 0 or launchd")
if let own = ProcessIdentity.read(getpid()) {
    expect(own.isCurrent, "Own process identity can be verified")
    expect(!ProcessControl.signal(own, force: false), "Must refuse to terminate itself")
} else { expect(false, "Own process metadata unavailable") }

// Signals are tested exclusively against child fixtures started by this test.
for force in [false, true] {
    let child = Process()
    child.executableURL = URL(fileURLWithPath: "/bin/sleep")
    child.arguments = ["30"]
    try child.run()
    guard let identity = ProcessIdentity.read(child.processIdentifier) else { child.terminate(); expect(false, "Child identity missing"); exit(1) }
    let stale = ProcessIdentity(pid: identity.pid, user: identity.user, startedSeconds: identity.startedSeconds + 1, startedMicros: identity.startedMicros)
    expect(!ProcessControl.signal(stale, force: force), "Reject recycled/stale PID identity")
    let otherUser = ProcessIdentity(pid: identity.pid, user: identity.user + 1, startedSeconds: identity.startedSeconds, startedMicros: identity.startedMicros)
    expect(!ProcessControl.signal(otherUser, force: force), "Reject a different user")
    expect(child.isRunning, "Rejected actions leave the fixture alive")
    expect(ProcessControl.signal(identity, force: force), "Can terminate the exact owned child fixture")
    child.waitUntilExit()
    expect(child.terminationReason == .uncaughtSignal, "Fixture terminated by a signal")
    expect(child.terminationStatus == (force ? SIGKILL : SIGTERM), "Requested termination mode")
}
guard let live = MemoryMonitor().sample() else { expect(false, "Live memory measurement failed"); exit(1) }
expect(live.total == ProcessInfo.processInfo.physicalMemory && live.total > 0, "Read actual physical memory")
expect(live.used > 0, "Read live used memory")
let processes = ProcessScanner().top()
expect(!processes.isEmpty, "Read a live process list")
expect(zip(processes, processes.dropFirst()).allSatisfy { $0.bytes >= $1.bytes }, "Sort by descending footprint")
expect(processes.flatMap(\.members).allSatisfy { $0.user == getuid() && $0.pid != getpid() }, "Only expose owned processes, excluding self")
print("PASS · \(checks) RAM checks, including live measurement and own child termination. No personal apps were terminated.")
