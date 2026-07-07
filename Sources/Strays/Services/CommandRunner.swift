import Foundation

/// Runs a short-lived command line tool off the main thread and returns its
/// stdout as a string. Errors and non-zero exits resolve to an empty string —
/// callers treat "no output" as "nothing found", which is the right behavior
/// for `lsof`/`ps` (they exit non-zero when nothing matches).
enum CommandRunner {
    static func run(_ launchPath: String, _ arguments: [String]) async -> String {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: launchPath)
                process.arguments = arguments

                let stdout = Pipe()
                process.standardOutput = stdout
                process.standardError = Pipe() // swallow stderr

                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: "")
                    return
                }

                // Read to end before waiting to avoid a full-pipe deadlock.
                let data = stdout.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                continuation.resume(returning: String(data: data, encoding: .utf8) ?? "")
            }
        }
    }
}
