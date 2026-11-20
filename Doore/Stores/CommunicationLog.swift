import Foundation
import Observation

/// Records communication metadata in the app container. All instances share one writer,
/// including windows that happen to log to the same file.
@MainActor @Observable
final class CommunicationLog {
    private(set) var url: URL?

    private let directory: URL?
    private let now: () -> Date
    private static let writer = DispatchQueue(label: "Doore.CommunicationLog", qos: .utility)

    init(directory: URL? = nil, now: @escaping () -> Date = Date.init) {
        self.directory = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Doore/Logs", isDirectory: true)
        self.now = now
    }

    /// Callers supply message types, sequence numbers or connection states only.
    /// Bodies, endpoint addresses, credentials and robot-provided error text are private.
    func record(_ message: String) {
        guard let directory, !message.isEmpty, message.utf8.count <= 256,
              !message.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
        else { return }
        let timestamp = now()
        let day = timestamp.formatted(Date.ISO8601FormatStyle(timeZone: .current).year().month().day())
        let file = directory.appendingPathComponent("\(day).log")
        let line = Data("\(timestamp.formatted(.iso8601)) \(message)\n".utf8)
        Self.writer.async { [weak self] in
            do {
                let manager = FileManager.default
                try manager.createDirectory(at: directory, withIntermediateDirectories: true)
                if !manager.fileExists(atPath: file.path) {
                    try line.write(to: file, options: .withoutOverwriting)
                } else {
                    let handle = try FileHandle(forWritingTo: file)
                    defer { try? handle.close() }
                    try handle.seekToEnd()
                    try handle.write(contentsOf: line)
                }
                DispatchQueue.main.async { [weak self] in
                    if self?.url != file { self?.url = file }
                }
            } catch {
                // Losing local diagnostics must never interrupt the connection.
            }
        }
    }
}
