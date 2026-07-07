import Darwin
import Foundation

/// Sends termination signals to processes by PID via the `kill(2)` syscall.
enum ProcessKiller {

    enum Outcome: Equatable {
        case success
        case notPermitted   // EPERM — usually a root/other-user process
        case noSuchProcess  // ESRCH — already gone
        case failure(Int32)

        var userMessage: String {
            switch self {
            case .success: return "Terminated"
            case .notPermitted: return "Not permitted — this process is owned by the system or another user."
            case .noSuchProcess: return "The process is no longer running."
            case .failure(let code): return "Failed to terminate (error \(code))."
            }
        }
    }

    /// Graceful (SIGTERM) by default; `force` uses SIGKILL.
    @discardableResult
    static func terminate(pid: Int32, force: Bool = false) -> Outcome {
        let signal = force ? SIGKILL : SIGTERM
        let result = kill(pid, signal)
        if result == 0 { return .success }
        switch errno {
        case EPERM: return .notPermitted
        case ESRCH: return .noSuchProcess
        default: return .failure(errno)
        }
    }

    /// Whether the current user is likely allowed to kill this process
    /// (same login owner). System/root processes will report `.notPermitted`.
    static func likelyKillable(user: String) -> Bool {
        user == NSUserName()
    }
}
