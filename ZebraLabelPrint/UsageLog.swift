import AppKit
import Foundation

/// Append-only local usage log. Counts and choices only — never file contents, paths, or printer names.
enum UsageLog {
    static var fileURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("ZebraLabelPrint", isDirectory: true)
            .appendingPathComponent("usage.jsonl")
    }()

    private static var didLaunch = false
    private static let iso: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func launch() {
        guard !didLaunch else { return }
        didLaunch = true
        record("launch")
    }

    /// A control the user actually touched. `value` is the choice (scope, size id, millimetres), never label text.
    static func ui(_ control: String, _ value: String = "") {
        record("ui", value.isEmpty ? ["control": control] : ["control": control, "value": value])
    }

    static func line(event: String, fields: [String: String] = [:], at date: Date = Date()) -> String {
        var payload: [String: String] = ["t": iso.string(from: date), "e": event]
        for (key, value) in fields where !value.isEmpty {
            payload[key] = value
        }
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else {
            return ""
        }
        return text
    }

    static func record(_ event: String, _ fields: [String: String] = [:]) {
        let text = line(event: event, fields: fields)
        guard !text.isEmpty else { return }
        let url = fileURL
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let lineData = Data((text + "\n").utf8)
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: lineData)
            return
        }
        try? lineData.write(to: url)
    }

    static func reveal() {
        let url = fileURL
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if !FileManager.default.fileExists(atPath: url.path) {
            try? Data().write(to: url)
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
