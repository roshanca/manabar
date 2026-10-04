import Foundation
import OSLog

/// Diagnostics for subprocess failures (status + tool's own error text only).
enum SecurityCLILogger {
    private static let logger = Logger(subsystem: "com.roshan.manabar", category: "security-cli")

    static func log(path: String, status: Int32, message: String) {
        logger.error("\(path, privacy: .public) exited \(status): \(message, privacy: .public)")
    }
}

/// Bounded wrapper around /usr/bin/security for reading credentials owned by
/// other CLIs (Claude Code stores its OAuth token in the login keychain).
/// The first read triggers the system keychain authorization prompt — expected.
enum SecurityCLI {
    static func findGenericPassword(service: String, account: String?) -> String? {
        var arguments = ["find-generic-password", "-s", service]
        if let account, !account.isEmpty { arguments += ["-a", account] }
        arguments.append("-w")
        return run("/usr/bin/security", arguments)
    }

    /// Updates (or creates) an item. Best-effort: callers must tolerate failure.
    @discardableResult
    static func setGenericPassword(service: String, account: String?, value: String) -> Bool {
        var arguments = ["add-generic-password", "-U", "-s", service]
        if let account, !account.isEmpty { arguments += ["-a", account] }
        arguments += ["-w", value]
        return run("/usr/bin/security", arguments) != nil
    }

    static func sqliteReadOnly(database: String, query: String) -> String? {
        run("/usr/bin/sqlite3", ["file:\(database)?mode=ro", query])
    }

    private static func run(_ path: String, _ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        do { try process.run() } catch {
            SecurityCLILogger.log(path: path, status: -1, message: "spawn failed: \(error.localizedDescription)")
            return nil
        }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            // stderr of /usr/bin/security carries only an error description, never secrets.
            let message = String(data: errorData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            SecurityCLILogger.log(path: path, status: process.terminationStatus, message: message)
            return nil
        }
        let output = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return output?.isEmpty == false ? output : nil
    }
}
