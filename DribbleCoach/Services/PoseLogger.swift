import Foundation
import DribbleCore

/// In Debug mode, writes every raw pose frame to a JSON-lines file, one frame per line,
/// so M3's fusion and head tracking can be tuned on real data before the M5 recorder exists.
///
/// Files go to Documents/PoseLogs and can be copied off with the Files app or Finder.
final class PoseLogger {
    private let queue = DispatchQueue(label: "dribblecoach.poselog", qos: .utility)
    private var handle: FileHandle?
    private let encoder = JSONEncoder()

    static var directory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PoseLogs", isDirectory: true)
    }

    /// Opens a new file named after the time and the drill. Any open file is closed first.
    func start(label: String) {
        queue.async {
            self.closeNow()
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
            let url = Self.directory.appendingPathComponent("\(formatter.string(from: Date()))_\(label).jsonl")
            do {
                try FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
                FileManager.default.createFile(atPath: url.path, contents: nil)
                self.handle = try FileHandle(forWritingTo: url)
            } catch {
                self.handle = nil
            }
        }
    }

    /// Adds one frame as a line of JSON.
    func log(_ frame: PoseFrame) {
        queue.async {
            guard let handle = self.handle, var data = try? self.encoder.encode(frame) else { return }
            data.append(0x0A)
            handle.write(data)
        }
    }

    func stop() {
        queue.async { self.closeNow() }
    }

    private func closeNow() {
        try? handle?.close()
        handle = nil
    }

    static func deleteAll() {
        try? FileManager.default.removeItem(at: directory)
    }
}
