import Darwin
import Foundation

/// A live inbound/peer connection to a listening port.
struct Connection: Identifiable, Hashable {
    let id = UUID()
    let peer: String       // remote endpoint, e.g. "192.168.1.20:52344"
    let command: String    // process on our side handling it
    let pid: Int32
}

/// Resolves who is currently connected to a given port. Run ONLY for the
/// selected row to keep polling cost bounded.
struct ConnectionResolver {
    func connections(forPort port: Int, excludingPID: Int32) async -> [Connection] {
        let output = await CommandRunner.run(
            PortScanner.lsofPath,
            ["-nP", "-iTCP:\(port)", "-sTCP:ESTABLISHED", "-Fpcn"]
        )
        return Self.parse(output)
    }

    /// Established-connection counts for every local port, in ONE lsof call —
    /// cheap enough to run each refresh, and the basis for idle detection.
    func inboundCounts() async -> [Int: Int] {
        let output = await CommandRunner.run(
            PortScanner.lsofPath,
            ["-nP", "-iTCP", "-sTCP:ESTABLISHED", "-Fn"]
        )
        return Self.parseCounts(output)
    }

    static func parseCounts(_ output: String) -> [Int: Int] {
        var counts: [Int: Int] = [:]
        for line in output.split(separator: "\n", omittingEmptySubsequences: true) where line.first == "n" {
            let value = line.dropFirst()
            guard let arrow = value.range(of: "->") else { continue }
            let local = value[value.startIndex..<arrow.lowerBound]  // localIP:localPort
            guard let colon = local.lastIndex(of: ":"),
                  let port = Int(local[local.index(after: colon)...]) else { continue }
            counts[port, default: 0] += 1
        }
        return counts
    }

    static func parse(_ output: String) -> [Connection] {
        var result: [Connection] = []
        var seen = Set<String>()
        var pid: Int32 = 0
        var command = ""
        for rawLine in output.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let tag = rawLine.first else { continue }
            let value = String(rawLine.dropFirst())
            switch tag {
            case "p": pid = Int32(value) ?? 0
            case "c": command = value
            case "n":
                // Established sockets look like "local->remote".
                guard let arrow = value.range(of: "->") else { continue }
                let peer = String(value[arrow.upperBound...])
                if seen.insert(peer).inserted {
                    result.append(Connection(peer: peer, command: command, pid: pid))
                }
            default: break
            }
        }
        return result
    }
}

/// Best-effort discovery of the machine's primary LAN IPv4 address, used to
/// make the "exposed to network" banner concrete ("reachable at 192.168.1.x").
enum NetworkInfo {
    static func primaryLANAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        var pointer: UnsafeMutablePointer<ifaddrs>? = first
        while let current = pointer {
            let flags = Int32(current.pointee.ifa_flags)
            let addr = current.pointee.ifa_addr
            if let addr, (flags & IFF_UP) == IFF_UP, (flags & IFF_LOOPBACK) == 0 {
                let family = addr.pointee.sa_family
                if family == UInt8(AF_INET) {
                    let name = String(cString: current.pointee.ifa_name)
                    if name == "en0" || name == "en1" {
                        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                        if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                            address = String(cString: host)
                        }
                    }
                }
            }
            pointer = current.pointee.ifa_next
        }
        return address
    }
}
