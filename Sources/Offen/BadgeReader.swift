import Foundation

struct BadgeReader {
    func read(pid: Int32) -> (label: String?, readable: Bool) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/lsappinfo")
        // A PID specifier is unambiguous even when two applications have the same name.
        process.arguments = ["info", "-only", "StatusLabel", "#\(pid)"]
        let pipe = Pipe()
        process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return (nil, false) }
        let deadline = ProcessInfo.processInfo.systemUptime + 1.5
        while process.isRunning && ProcessInfo.processInfo.systemUptime < deadline { Thread.sleep(forTimeInterval: 0.01) }
        if process.isRunning { process.terminate(); return (nil, false) }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0, let output = String(data: data, encoding: .utf8),
              !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return (nil, false) }
        return (Self.label(in: output), true)
    }

    static func label(in output: String) -> String? {
        guard let expression = try? NSRegularExpression(pattern: #""label"\s*=\s*"([^"]*)""#),
              let match = expression.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)),
              let range = Range(match.range(at: 1), in: output) else { return nil }
        return String(output[range])
    }
}
