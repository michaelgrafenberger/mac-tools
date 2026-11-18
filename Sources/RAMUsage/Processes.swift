import Cocoa
import Darwin

struct MemoryProcess: Identifiable {
    let id: String
    let name: String
    let appPath: String?
    var members: [ProcessIdentity]
    var bytes: UInt64
    let icon: NSImage
    var count: Int { members.count }
}

final class ProcessScanner {
    private var icons: [String: NSImage] = [:]
    func top(_ limit: Int = 12) -> [MemoryProcess] {
        let estimate = proc_listallpids(nil, 0)
        guard estimate > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(estimate) + 128)
        let count = Int(proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size)))
        guard count > 0 else { return [] }
        let ownPath = Bundle.main.bundleURL.resolvingSymlinksInPath().path
        var groups: [String: MemoryProcess] = [:]
        for pid in pids.prefix(count) where pid > 1 && pid != getpid() {
            guard let identity = ProcessIdentity.read(pid), identity.user == getuid(), let bytes = footprint(pid), bytes > 0 else { continue }
            let executable = ProcessControl.path(pid)
            let processName = (executable as NSString).lastPathComponent
            guard !executable.isEmpty, !ProcessControl.protected.contains(processName) else { continue }
            let appPath = Self.appBundle(in: executable).map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path }
            if appPath == ownPath { continue }
            if let appPath, ProcessControl.protected.contains(URL(fileURLWithPath: appPath).deletingPathExtension().lastPathComponent) { continue }
            let id = appPath ?? "pid:\(pid)"
            if var group = groups[id] {
                group.members.append(identity)
                let sum = group.bytes.addingReportingOverflow(bytes)
                group.bytes = sum.overflow ? UInt64.max : sum.partialValue
                groups[id] = group
            } else {
                let name = appPath.map { FileManager.default.displayName(atPath: $0) } ?? processName
                let iconPath = appPath ?? executable
                if icons[iconPath] == nil { icons[iconPath] = NSWorkspace.shared.icon(forFile: iconPath) }
                groups[id] = MemoryProcess(id: id, name: name.hasSuffix(".app") ? String(name.dropLast(4)) : name, appPath: appPath,
                                           members: [identity], bytes: bytes, icon: icons[iconPath] ?? NSImage())
            }
        }
        return groups.values.sorted { $0.bytes > $1.bytes }.prefix(limit).map { $0 }
    }

    static func appBundle(in path: String) -> String? {
        guard let range = path.range(of: ".app/") else { return nil }
        return String(path[..<range.lowerBound]) + ".app"
    }
    private func footprint(_ pid: pid_t) -> UInt64? {
        var info = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V4, $0) }
        }
        return result == 0 ? info.ri_phys_footprint : nil
    }
}
