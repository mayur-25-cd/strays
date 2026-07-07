import Foundation

/// Discovers listening TCP ports and enriches each owning process with its
/// working directory, full launch command and start time.
///
/// Three cheap subprocess calls per scan:
///   1. `lsof` — listening sockets (pid, command, user, family, address:port)
///   2. `lsof` — batched cwd for all discovered pids
///   3. `ps`   — batched full command + start time for all discovered pids
struct PortScanner {

    static let lsofPath = "/usr/sbin/lsof"
    static let psPath = "/bin/ps"

    func scan() async -> [ListeningProcess] {
        let listing = await CommandRunner.run(
            Self.lsofPath,
            ["-nP", "-iTCP", "-sTCP:LISTEN", "-FpcLtPn"]
        )
        var processes = Self.parseListening(listing)
        guard !processes.isEmpty else { return [] }

        let pids = processes.map { String($0.pid) }.joined(separator: ",")

        async let cwdOutput = CommandRunner.run(Self.lsofPath, ["-a", "-p", pids, "-d", "cwd", "-Fpn"])
        async let psOutput = CommandRunner.run(Self.psPath, ["-ww", "-o", "pid=,%cpu=,rss=,lstart=,command=", "-p", pids])

        let cwds = Self.parseCwds(await cwdOutput)
        let details = Self.parsePS(await psOutput)

        for index in processes.indices {
            let pid = processes[index].pid
            processes[index].workingDirectory = cwds[pid]
            if let detail = details[pid] {
                processes[index].fullCommand = detail.command
                processes[index].startDate = detail.start
                processes[index].cpuPercent = detail.cpu
                processes[index].memoryKB = detail.rss
            }
            let (category, framework) = ProcessClassifier.classify(
                command: processes[index].command,
                fullCommand: processes[index].fullCommand
            )
            processes[index].category = category
            processes[index].framework = framework
        }

        return processes
    }

    // MARK: - lsof listening parse

    static func parseListening(_ output: String) -> [ListeningProcess] {
        var byPid: [Int32: ListeningProcess] = [:]
        var order: [Int32] = []

        var curPid: Int32?
        var curCommand = ""
        var curUser = ""
        var curFamily: NetFamily = .other
        var curProto = "TCP"

        for rawLine in output.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let tag = rawLine.first else { continue }
            let value = String(rawLine.dropFirst())

            switch tag {
            case "p":
                curPid = Int32(value)
                curCommand = ""
                curUser = ""
            case "c":
                curCommand = decodeLsofName(value)
            case "L":
                curUser = value
            case "f":
                // Start of a new open-file record; reset per-file state.
                curFamily = .other
                curProto = "TCP"
            case "t":
                curFamily = NetFamily(rawValue: value) ?? .other
            case "P":
                curProto = value
            case "n":
                guard let pid = curPid,
                      let binding = parseBinding(name: value, family: curFamily, proto: curProto)
                else { continue }
                if byPid[pid] == nil {
                    byPid[pid] = ListeningProcess(
                        pid: pid,
                        command: curCommand,
                        user: curUser,
                        bindings: []
                    )
                    order.append(pid)
                }
                if !byPid[pid]!.bindings.contains(binding) {
                    byPid[pid]!.bindings.append(binding)
                }
            default:
                break
            }
        }

        return order.compactMap { byPid[$0] }
    }

    /// Splits an "address:port" name from lsof into a binding. IPv6 addresses
    /// arrive bracketed (`[::1]:5432`), so we split on the final colon.
    static func parseBinding(name: String, family: NetFamily, proto: String) -> PortBinding? {
        guard let lastColon = name.lastIndex(of: ":") else { return nil }
        let address = String(name[name.startIndex..<lastColon])
        let portString = String(name[name.index(after: lastColon)...])
        guard let port = Int(portString), port > 0 else { return nil } // skips "*:*" etc.
        return PortBinding(port: port, address: address, family: family, networkProtocol: proto)
    }

    /// lsof escapes some characters in names as `\xNN`; decode the common ones
    /// so command labels like "Code\x20Helper" read as "Code Helper".
    static func decodeLsofName(_ value: String) -> String {
        guard value.contains("\\x") else { return value }
        return value.replacingOccurrences(of: "\\x20", with: " ")
    }

    // MARK: - cwd parse

    static func parseCwds(_ output: String) -> [Int32: String] {
        var result: [Int32: String] = [:]
        var curPid: Int32?
        for rawLine in output.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let tag = rawLine.first else { continue }
            let value = String(rawLine.dropFirst())
            switch tag {
            case "p": curPid = Int32(value)
            case "n": if let pid = curPid, result[pid] == nil { result[pid] = value }
            default: break
            }
        }
        return result
    }

    // MARK: - ps parse

    struct ProcessDetail {
        let command: String
        let start: Date?
        let cpu: Double?
        let rss: Int?   // resident memory, KB
    }

    private static let lstartFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE MMM d HH:mm:ss yyyy"
        return formatter
    }()

    static func parsePS(_ output: String) -> [Int32: ProcessDetail] {
        var result: [Int32: ProcessDetail] = [:]
        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            // Layout: "<pid> <%cpu> <rss> <Weekday Mon DD HH:MM:SS YYYY> <command...>"
            let tokens = line.split(separator: " ", omittingEmptySubsequences: true)
            guard tokens.count >= 9, let pid = Int32(tokens[0]) else { continue }
            let cpu = Double(tokens[1])
            let rss = Int(tokens[2])
            let lstart = tokens[3...7].joined(separator: " ")
            let command = tokens[8...].joined(separator: " ")
            result[pid] = ProcessDetail(command: command, start: lstartFormatter.date(from: lstart), cpu: cpu, rss: rss)
        }
        return result
    }
}
