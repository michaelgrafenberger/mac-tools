import Foundation
import Darwin

enum NetworkReader {
    /// 64-bit kernel counters, rather than the wrapping 32-bit getifaddrs counters.
    static func read() -> [String: TrafficCounter]? {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        for _ in 0..<3 {
            var size = 0
            guard sysctl(&mib, UInt32(mib.count), nil, &size, nil, 0) == 0 else { return nil }
            guard size > 0 else { return [:] }
            let buffer = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: MemoryLayout<if_msghdr2>.alignment)
            defer { buffer.deallocate() }
            guard sysctl(&mib, UInt32(mib.count), buffer, &size, nil, 0) == 0 else {
                if errno == ENOMEM { continue }; return nil
            }
            var offset = 0
            var counters: [String: TrafficCounter] = [:]
            while offset + 4 <= size {
                let length = Int(buffer.loadUnaligned(fromByteOffset: offset, as: UInt16.self))
                guard length >= 4, offset + length <= size else { return nil }
                let type = buffer.load(fromByteOffset: offset + 3, as: UInt8.self)
                if type == UInt8(RTM_IFINFO2), length >= MemoryLayout<if_msghdr2>.size {
                    let info = buffer.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                    if (info.ifm_flags & IFF_UP) != 0 {
                        var characters = [CChar](repeating: 0, count: Int(IFNAMSIZ))
                        if if_indextoname(UInt32(info.ifm_index), &characters) != nil {
                            let name = String(cString: characters)
                            // Exclude loopback, VPN tunnels and peer-to-peer interfaces to avoid duplicate traffic.
                            if name.hasPrefix("en") || name.hasPrefix("pdp_ip") {
                                counters[name] = TrafficCounter(received: info.ifm_data.ifi_ibytes, sent: info.ifm_data.ifi_obytes)
                            }
                        }
                    }
                }
                offset += length
            }
            return counters
        }
        return nil
    }
}
