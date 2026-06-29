import AppKit
import Foundation

enum PrinterQueueStatus: Equatable {
    case ready
    case paused
    case offline
    case unknown

    var shortLabel: String {
        switch self {
        case .ready:
            return "Queue ready"
        case .paused:
            return "Queue paused"
        case .offline:
            return "Printer offline"
        case .unknown:
            return "Queue status unknown"
        }
    }

    var detail: String {
        switch self {
        case .ready:
            return "Accepting print jobs."
        case .paused:
            return "Jobs will queue but nothing prints until the queue is resumed."
        case .offline:
            return "Check that the printer is connected and powered on."
        case .unknown:
            return "Could not read the queue status."
        }
    }

    var blocksPrinting: Bool {
        switch self {
        case .ready, .unknown:
            return false
        case .paused, .offline:
            return true
        }
    }
}

// thin wrapper around lpstat / lpr — nothing fancy here
enum CUPSPrinterService {
    enum PrintError: LocalizedError {
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .failed(let message):
                return message
            }
        }
    }

    enum PrintSubmissionResult {
        case sent
        case queuedWhilePaused
    }

    static func printerNames() -> [String] {
        // queue names from CUPS, not the friendly name in System Settings
        guard let output = runCommand(executable: "/usr/bin/lpstat", arguments: ["-a"]) else {
            return []
        }

        return parseQueueNames(from: output)
    }

    static func isSchedulerRunning() -> Bool {
        guard let output = runCommand(executable: "/usr/bin/lpstat", arguments: ["-r"]) else {
            return false
        }

        let lower = output.lowercased()
        // lpstat -r text is localized; match known “not running” phrases.
        if lower.contains("not running") || lower.contains("ne s'exécute pas") || lower.contains("ne s’exécute pas") {
            return false
        }
        return true
    }

    static func zebraPrinterNames() -> [String] {
        printerNames().filter { name in
            name.range(of: "zebra", options: .caseInsensitive) != nil
        }
    }

    static func printerQueueStatus(_ printer: String) -> PrinterQueueStatus {
        guard !printer.isEmpty else { return .unknown }

        if let options = runCommand(executable: "/usr/bin/lpoptions", arguments: ["-p", printer]) {
            if options.contains("printer-state-reasons=paused")
                || options.contains("printer-state-reasons=hold")
                || options.contains("printer-state-reasons=stopped") {
                return .paused
            }
            if options.contains("printer-state-reasons=offline-report") {
                return .offline
            }
        }

        if let lpstatOutput = runCommand(executable: "/usr/bin/lpstat", arguments: ["-p", printer]) {
            let lower = lpstatOutput.lowercased()
            if lower.contains("offline") || lower.contains("hors ligne") {
                return .offline
            }
            if lower.contains("disabled")
                || lower.contains("désactiv")
                || lower.contains("paused")
                || lower.contains("en pause") {
                return .paused
            }
            return .ready
        }

        return .unknown
    }

    static func isPrinterAcceptingJobs(_ printer: String) -> Bool? {
        guard !printer.isEmpty else { return nil }
        let status = printerQueueStatus(printer)
        switch status {
        case .ready:
            return true
        case .paused, .offline:
            return false
        case .unknown:
            return nil
        }
    }

    @discardableResult
    static func resumePrinterQueue(_ printer: String) -> Bool {
        guard !printer.isEmpty else { return false }
        _ = runCommand(executable: "/usr/sbin/cupsenable", arguments: [printer])
        _ = runCommand(executable: "/usr/sbin/cupsaccept", arguments: [printer])
        return printerQueueStatus(printer) == .ready
    }

    @discardableResult
    static func pausePrinterQueue(_ printer: String) -> Bool {
        guard !printer.isEmpty else { return false }
        _ = runCommand(executable: "/usr/sbin/cupsdisable", arguments: [printer])
        return printerQueueStatus(printer) == .paused
    }

    @discardableResult
    static func cancelAllJobs(on printer: String) -> Bool {
        guard !printer.isEmpty else { return false }
        return runCommand(executable: "/usr/bin/cancel", arguments: ["-a", printer]) != nil
            || pendingJobCount(for: printer) == 0
    }

    static func pendingJobCount(for printer: String) -> Int {
        guard !printer.isEmpty,
              let output = runCommand(executable: "/usr/bin/lpstat", arguments: ["-o", printer]) else {
            return 0
        }
        return output
            .split(separator: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .count
    }

    private static func parseQueueNames(from output: String) -> [String] {
        output
            .split(separator: "\n")
            .compactMap { line -> String? in
                let name = line.split(separator: " ", omittingEmptySubsequences: true).first
                return name.map(String.init)
            }
            .sorted()
    }

    @discardableResult
    static func printRaw(zplData: Data, to printer: String) -> Result<PrintSubmissionResult, PrintError> {
        guard printerNames().contains(printer) else {
            return .failure(.failed("Printer \"\(printer)\" was not found. Available: \(printerNames().joined(separator: ", "))"))
        }

        _ = resumePrinterQueue(printer)
        let wasPaused = printerQueueStatus(printer) != .ready

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("zebra-print-\(UUID().uuidString).zpl")

        do {
            try zplData.write(to: tempURL, options: .atomic)
        } catch {
            return .failure(.failed("Could not stage the print file: \(error.localizedDescription)"))
        }

        defer {
            try? FileManager.default.removeItem(at: tempURL)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/lpr")
        // -l = raw ZPL; pass a temp file path so the full job is submitted (stdin pipe truncated data).
        process.arguments = ["-P", printer, "-l", tempURL.path]

        let errorPipe = Pipe()
        process.standardError = errorPipe
        process.standardOutput = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()

            if process.terminationStatus == 0 {
                if wasPaused || printerQueueStatus(printer) != .ready {
                    return .success(.queuedWhilePaused)
                }
                return .success(.sent)
            }

            let stderr = readPipe(errorPipe)
            if stderr.isEmpty {
                return .failure(.failed("lpr exited with status \(process.terminationStatus)."))
            }
            return .failure(.failed(stderr))
        } catch {
            return .failure(.failed(error.localizedDescription))
        }
    }

    private static func runCommand(executable: String, arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            return readPipe(outputPipe)
        } catch {
            return nil
        }
    }

    enum AdminCommandError: LocalizedError {
        case failed(String)
        case cancelled

        var errorDescription: String? {
            switch self {
            case .failed(let message):
                return message
            case .cancelled:
                return "Administrator password was not provided."
            }
        }
    }

    static func restartCUPSScheduler() -> Result<Void, AdminCommandError> {
        runAdminShell("/bin/launchctl kickstart -k system/org.cups.cupsd")
    }

    private static func runAdminShell(_ command: String) -> Result<Void, AdminCommandError> {
        let escaped = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let source = "do shell script \"\(escaped)\" with administrator privileges"

        var errorInfo: NSDictionary?
        guard let script = NSAppleScript(source: source) else {
            return .failure(.failed("Could not prepare the administrator command."))
        }

        script.executeAndReturnError(&errorInfo)

        if let errorInfo {
            let code = errorInfo[NSAppleScript.errorNumber] as? Int ?? -1
            let message = errorInfo[NSAppleScript.errorMessage] as? String ?? "Administrator command failed."

            // -128 = user cancelled authentication
            if code == -128 {
                return .failure(.cancelled)
            }

            let lower = message.lowercased()
            if lower.contains("incorrect") && lower.contains("password") {
                return .failure(.failed(
                    "Administrator sign-in failed. Enter the password for a macOS administrator account on this Mac — not your Apple ID."
                ))
            }

            return .failure(.failed(message))
        }

        return .success(())
    }

    private static func readPipe(_ pipe: Pipe) -> String {
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}
