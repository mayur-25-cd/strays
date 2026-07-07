import Foundation

/// Incremental read state for one transcript — so an active 58 MB JSONL is read
/// once, then only appended deltas, never re-parsed whole.
private struct TranscriptCursor {
    var offset: UInt64 = 0
    var messages: Int = 0
    var inputTokens: Int = 0
    var outputTokens: Int = 0
    var cacheReadTokens: Int = 0
    var cacheCreationTokens: Int = 0
    var model: String?
    var gitBranch: String?
}

/// Discovers running AI coding sessions from tools' local files, proving each
/// live by cross-checking the recorded process start against the real one.
actor AISessionScanner {
    private let home = NSHomeDirectory()
    private var cursors: [String: TranscriptCursor] = [:]        // sessionId → cursor
    private var transcriptPaths: [String: String] = [:]          // sessionId → resolved path

    private let utcFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE MMM d HH:mm:ss yyyy"
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()
    private let localFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE MMM d HH:mm:ss yyyy"
        f.timeZone = .current
        return f
    }()

    func scan() async -> [AISession] {
        var sessions: [AISession] = []
        let claudeFiles = files(in: "\(home)/.claude/sessions", ext: "json")
        let copilotFiles = files(in: "\(home)/.copilot/ide", ext: "lock")

        // One ps call for every candidate PID → real local start time.
        var pids = Set<Int32>()
        let claudeDescriptors = claudeFiles.compactMap(parseClaudeSession)
        let copilotDescriptors = copilotFiles.compactMap(parseCopilotLock)
        claudeDescriptors.forEach { if let p = $0.pid { pids.insert(p) } }
        copilotDescriptors.forEach { if let p = $0.pid { pids.insert(p) } }
        let starts = await processStarts(for: pids)

        for d in claudeDescriptors {
            let live = isLive(pid: d.pid, recordedProcStart: d.procStart, starts: starts)
            var cursor = TranscriptCursor()
            var lastActivity = d.startedAt
            if live, let sid = d.sessionId {
                if let path = transcriptPath(sessionId: sid, cwd: d.cwd) {
                    cursor = readTranscriptDelta(sessionId: sid, path: path)
                    lastActivity = fileModified(path) ?? lastActivity
                }
            }
            let cost = live ? ClaudePricing.estimate(model: cursor.model,
                                                      input: cursor.inputTokens, output: cursor.outputTokens,
                                                      cacheRead: cursor.cacheReadTokens, cacheCreation: cursor.cacheCreationTokens) : nil
            sessions.append(AISession(
                tool: .claudeCode, sessionKey: d.sessionId ?? String(d.pid ?? 0), pid: d.pid,
                workingDirectory: d.cwd, model: cursor.model, isLive: live,
                startedAt: d.startedAt, lastActivity: lastActivity,
                messageCount: live ? cursor.messages : nil,
                inputTokens: live ? cursor.inputTokens : nil,
                outputTokens: live ? cursor.outputTokens : nil,
                cachedTokens: live ? (cursor.cacheReadTokens + cursor.cacheCreationTokens) : nil,
                estimatedCostUSD: cost, gitBranch: cursor.gitBranch))
        }

        for d in copilotDescriptors {
            let live = d.pid.map { starts[$0] != nil } ?? false
            sessions.append(AISession(
                tool: .copilotCLI, sessionKey: d.uuid, pid: d.pid,
                workingDirectory: d.workspace, model: nil, isLive: live,
                startedAt: d.timestamp, lastActivity: d.timestamp,
                messageCount: nil, inputTokens: nil, outputTokens: nil, cachedTokens: nil,
                estimatedCostUSD: nil, gitBranch: nil))
        }

        // Drop stale cursors for sessions that vanished.
        let liveIDs = Set(sessions.compactMap { $0.tool == .claudeCode ? $0.sessionKey : nil })
        cursors = cursors.filter { liveIDs.contains($0.key) }
        return sessions
    }

    // MARK: - Liveness (the load-bearing check, verified against real data)

    private func isLive(pid: Int32?, recordedProcStart: Date?, starts: [Int32: Date]) -> Bool {
        guard let pid, let recorded = recordedProcStart, let real = starts[pid] else { return false }
        // procStart is UTC, ps lstart is local — both parsed to absolute Dates here,
        // so a genuine process matches within a second; a recycled PID won't.
        return abs(real.timeIntervalSince(recorded)) < 2
    }

    private func processStarts(for pids: Set<Int32>) async -> [Int32: Date] {
        guard !pids.isEmpty else { return [:] }
        let csv = pids.map(String.init).joined(separator: ",")
        let output = await CommandRunner.run("/bin/ps", ["-o", "pid=,lstart=", "-p", csv])
        var result: [Int32: Date] = [:]
        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            let tokens = line.split(separator: " ", omittingEmptySubsequences: true)
            guard tokens.count >= 6, let pid = Int32(tokens[0]) else { continue }
            let lstart = tokens[1...5].joined(separator: " ")
            if let date = localFormatter.date(from: lstart) { result[pid] = date }
        }
        return result
    }

    // MARK: - Adapters

    private struct ClaudeDescriptor { let pid: Int32?; let cwd: String?; let sessionId: String?; let procStart: Date?; let startedAt: Date? }

    private func parseClaudeSession(_ path: String) -> ClaudeDescriptor? {
        guard let data = FileManager.default.contents(atPath: path),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let pid = (obj["pid"] as? Int).map(Int32.init)
        let procStart = (obj["procStart"] as? String).flatMap { utcFormatter.date(from: $0) }
        let startedMs = obj["startedAt"] as? Double
        let started = startedMs.map { Date(timeIntervalSince1970: $0 / 1000) }
        return ClaudeDescriptor(pid: pid, cwd: obj["cwd"] as? String, sessionId: obj["sessionId"] as? String, procStart: procStart, startedAt: started)
    }

    private struct CopilotDescriptor { let uuid: String; let pid: Int32?; let workspace: String?; let timestamp: Date? }

    private func parseCopilotLock(_ path: String) -> CopilotDescriptor? {
        guard let data = FileManager.default.contents(atPath: path),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let uuid = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        let pid = (obj["pid"] as? Int).map(Int32.init)
        var workspace: String?
        if let folders = obj["workspaceFolders"] as? [String], let first = folders.first {
            workspace = first.replacingOccurrences(of: "file://", with: "").removingPercentEncoding
        }
        let ts = (obj["timestamp"] as? Double).map { Date(timeIntervalSince1970: $0 > 1_000_000_000_000 ? $0 / 1000 : $0) }
        return CopilotDescriptor(uuid: uuid, pid: pid, workspace: workspace, timestamp: ts)
    }

    // MARK: - Transcript resolution + incremental read

    private func transcriptPath(sessionId: String, cwd: String?) -> String? {
        // A session id becomes a path component — never let it escape the tree.
        guard !sessionId.isEmpty, !sessionId.contains("/"), !sessionId.contains("..") else { return nil }
        if let cached = transcriptPaths[sessionId] { return cached }
        let projects = "\(home)/.claude/projects"
        // Fast path: Claude's slug is the cwd with non-alphanumerics → "-".
        if let cwd {
            let slug = cwd.map { $0.isLetter || $0.isNumber ? $0 : "-" }.reduce(into: "") { $0.append($1) }
            let guess = "\(projects)/\(slug)/\(sessionId).jsonl"
            if FileManager.default.fileExists(atPath: guess) { transcriptPaths[sessionId] = guess; return guess }
        }
        // Fallback: scan project dirs once.
        if let dirs = try? FileManager.default.contentsOfDirectory(atPath: projects) {
            for dir in dirs {
                let candidate = "\(projects)/\(dir)/\(sessionId).jsonl"
                if FileManager.default.fileExists(atPath: candidate) { transcriptPaths[sessionId] = candidate; return candidate }
            }
        }
        return nil
    }

    private func readTranscriptDelta(sessionId: String, path: String) -> TranscriptCursor {
        var cursor = cursors[sessionId] ?? TranscriptCursor()
        guard let handle = FileHandle(forReadingAtPath: path) else { return cursor }
        defer { try? handle.close() }
        let attrs = try? FileManager.default.attributesOfItem(atPath: path)
        let size = (attrs?[.size] as? NSNumber)?.uint64Value ?? 0
        if size < cursor.offset { cursor = TranscriptCursor() }   // file rotated/rewritten
        guard size > cursor.offset else { cursors[sessionId] = cursor; return cursor }

        // Read at most one chunk per tick so a huge first read can't spike memory
        // or stall the 2s loop; the rest is drained on subsequent ticks.
        let maxChunk = 64 * 1024 * 1024
        try? handle.seek(toOffset: cursor.offset)
        let data = (try? handle.read(upToCount: maxChunk)) ?? Data()
        guard !data.isEmpty else { return cursor }

        // Only consume through the last newline so we never parse a half-written line.
        guard let lastNewline = data.lastIndex(of: 0x0A) else {
            // No newline in a full chunk (pathological long line) — skip past it to make progress.
            if data.count >= maxChunk { cursor.offset += UInt64(data.count) }
            cursors[sessionId] = cursor
            return cursor
        }
        let complete = data[..<data.index(after: lastNewline)]
        cursor.offset += UInt64(complete.count)

        for lineData in complete.split(separator: 0x0A, omittingEmptySubsequences: true) {
            guard let obj = try? JSONSerialization.jsonObject(with: Data(lineData)) as? [String: Any] else { continue }
            let type = obj["type"] as? String
            if type == "user" || type == "assistant" { cursor.messages += 1 }
            if let branch = obj["gitBranch"] as? String, !branch.isEmpty { cursor.gitBranch = branch }
            if type == "assistant", let message = obj["message"] as? [String: Any] {
                if let model = message["model"] as? String { cursor.model = model }
                if let usage = message["usage"] as? [String: Any] {
                    cursor.inputTokens += usage["input_tokens"] as? Int ?? 0
                    cursor.outputTokens += usage["output_tokens"] as? Int ?? 0
                    cursor.cacheReadTokens += usage["cache_read_input_tokens"] as? Int ?? 0
                    cursor.cacheCreationTokens += usage["cache_creation_input_tokens"] as? Int ?? 0
                }
            }
        }
        cursors[sessionId] = cursor
        return cursor
    }

    // MARK: - Small helpers

    private func files(in dir: String, ext: String) -> [String] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return [] }
        return names.filter { $0.hasSuffix(".\(ext)") }.map { "\(dir)/\($0)" }
    }

    private func fileModified(_ path: String) -> Date? {
        let attrs = try? FileManager.default.attributesOfItem(atPath: path)
        return attrs?[.modificationDate] as? Date
    }
}

/// Rough, clearly-labeled Claude cost estimate (USD). Pricing is approximate and
/// per-model; only Claude Code emits clean structured usage, so this is Claude-only.
enum ClaudePricing {
    // (input, output, cacheRead, cacheWrite) per 1M tokens.
    private static func rates(for model: String) -> (Double, Double, Double, Double) {
        let m = model.lowercased()
        if m.contains("opus") { return (15, 75, 1.5, 18.75) }
        if m.contains("haiku") { return (0.80, 4, 0.08, 1.0) }
        return (3, 15, 0.30, 3.75)   // sonnet / default
    }

    static func estimate(model: String?, input: Int, output: Int, cacheRead: Int, cacheCreation: Int) -> Double? {
        guard let model, input + output + cacheRead + cacheCreation > 0 else { return nil }
        let (ri, ro, rcr, rcw) = rates(for: model)
        return (Double(input) * ri + Double(output) * ro + Double(cacheRead) * rcr + Double(cacheCreation) * rcw) / 1_000_000
    }
}
