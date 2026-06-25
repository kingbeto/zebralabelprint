import Foundation

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

    static func printerNames() -> [String] {
        // queue names from CUPS, not the friendly name in System Settings
        guard let output = runCommand(executable: "/usr/bin/lpstat", arguments: ["-a"]) else {
            return []
        }

        return output
            .split(separator: "\n")
            .compactMap { line -> String? in
                let name = line.split(separator: " ", omittingEmptySubsequences: true).first
                return name.map(String.init)
            }
            .sorted()
    }

    @discardableResult
    static func printRaw(zplData: Data, to printer: String) -> Result<Void, PrintError> {
        guard printerNames().contains(printer) else {
            return .failure(.failed("Printer \"\(printer)\" was not found. Available: \(printerNames().joined(separator: ", "))"))
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/lpr")
        // -l = raw ZPL, dont let CUPS try to be clever
        process.arguments = ["-P", printer, "-l"]

        let inputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardInput = inputPipe
        process.standardError = errorPipe
        process.standardOutput = FileHandle.nullDevice

        do {
            try process.run()
            // pipe zpl on stdin — file path approach broke under sandbox
            inputPipe.fileHandleForWriting.write(zplData)
            inputPipe.fileHandleForWriting.closeFile()
            process.waitUntilExit()

            if process.terminationStatus == 0 {
                return .success(())
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

    private static func readPipe(_ pipe: Pipe) -> String {
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}
