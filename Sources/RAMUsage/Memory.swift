import Foundation
import Darwin

struct MemorySnapshot {
    let total: UInt64
    let app: UInt64
    let wired: UInt64
    let compressed: UInt64
    let cached: UInt64
    let swapUsed: UInt64?
    let pressure: Int32?
    var used: UInt64 { app + wired + compressed }
    var percent: Double { total > 0 ? Double(used) / Double(total) * 100 : 0 }
    var pressureText: String {
        switch pressure { case 1: return "Normal"; case 2: return "Erhöht"; case 4: return "Kritisch"; default: return "Nicht verfügbar" }
    }
}

enum MemoryFormat {
    static func gb(_ bytes: UInt64) -> String {
        String(format: "%.1f", locale: Locale(identifier: "de_AT"), Double(bytes) / 1_073_741_824)
    }
    static func string(_ bytes: UInt64) -> String {
        if bytes >= 1_073_741_824 { return "\(gb(bytes)) GB" }
        return "\(Int((Double(bytes) / 1_048_576).rounded())) MB"
    }
}

final class MemoryMonitor {
    private let host = mach_host_self()
    private let pageSize: UInt64
    init() {
        var size: vm_size_t = 0
        host_page_size(host, &size)
        pageSize = UInt64(size)
    }
    deinit { mach_port_deallocate(mach_task_self_, host) }

    func sample() -> MemorySnapshot? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics64(host, HOST_VM_INFO64, $0, &count) }
        }
        guard result == KERN_SUCCESS, pageSize > 0 else { return nil }
        let internalPages = UInt64(stats.internal_page_count), purgeable = UInt64(stats.purgeable_count)
        var swap = xsw_usage(), swapSize = MemoryLayout<xsw_usage>.size
        let swapOK = sysctlbyname("vm.swapusage", &swap, &swapSize, nil, 0) == 0
        var pressure: Int32 = 0, pressureSize = MemoryLayout<Int32>.size
        let pressureOK = sysctlbyname("kern.memorystatus_vm_pressure_level", &pressure, &pressureSize, nil, 0) == 0
        return MemorySnapshot(total: ProcessInfo.processInfo.physicalMemory,
                              app: (internalPages > purgeable ? internalPages - purgeable : 0) * pageSize,
                              wired: UInt64(stats.wire_count) * pageSize,
                              compressed: UInt64(stats.compressor_page_count) * pageSize,
                              cached: (UInt64(stats.external_page_count) + purgeable) * pageSize,
                              swapUsed: swapOK ? swap.xsu_used : nil, pressure: pressureOK ? pressure : nil)
    }
}

struct ProcessIdentity: Equatable {
    let pid: pid_t
    let user: uid_t
    let startedSeconds: UInt64
    let startedMicros: UInt64

    static func read(_ pid: pid_t) -> ProcessIdentity? {
        guard pid > 1 else { return nil }
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return ProcessIdentity(pid: pid, user: info.pbi_uid, startedSeconds: info.pbi_start_tvsec, startedMicros: info.pbi_start_tvusec)
    }
    var isCurrent: Bool { Self.read(pid) == self }
}

enum ProcessControl {
    static let protected: Set<String> = ["loginwindow", "WindowServer", "Dock", "launchd", "kernel_task", "SystemUIServer",
                                          "tccd", "securityd", "coreauthd", "runningboardd", "cfprefsd", "distnoted", "notifyd"]
    static func path(_ pid: pid_t) -> String {
        var buffer = [CChar](repeating: 0, count: 4096)
        return proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 ? String(cString: buffer) : ""
    }
    static func signal(_ process: ProcessIdentity, force: Bool) -> Bool {
        // Revalidate owner AND process start time: a recycled PID must never target a new process.
        guard process.pid != getpid(), process.user == getuid(), process.isCurrent else { return false }
        let executable = path(process.pid)
        guard !executable.isEmpty, !protected.contains((executable as NSString).lastPathComponent) else { return false }
        return kill(process.pid, force ? SIGKILL : SIGTERM) == 0
    }
}
