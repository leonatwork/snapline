import Foundation
import SnaplineCore

/// File I/O stays in the app; the rotation decision is pure Core logic.
final class DebugLogFile {
    static let shared = DebugLogFile(url: FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/Snapline/debug.log"))

    private let url: URL
    private let lock = NSLock()

    init(url: URL) { self.url = url }

    func append(_ data: Data) throws {
        // Keep size checks, rotation and appends together even if diagnostics
        // are later called from more than one thread.
        lock.lock()
        defer { lock.unlock() }
        let manager = FileManager.default
        let backup = url.appendingPathExtension("1")
        let permissions: [FileAttributeKey: Any] = [.posixPermissions: 0o600]

        try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if manager.fileExists(atPath: backup.path) {
            try manager.setAttributes(permissions, ofItemAtPath: backup.path)
        }
        if manager.fileExists(atPath: url.path) {
            // Harden existing logs before they can become the retained backup.
            // If permissions or rotation fail, do not append diagnostic data.
            try manager.setAttributes(permissions, ofItemAtPath: url.path)
            let attributes = try manager.attributesOfItem(atPath: url.path)
            if let size = attributes[.size] as? NSNumber,
               DebugLogRotation.shouldRotate(fileSize: size.uint64Value) {
                if manager.fileExists(atPath: backup.path) {
                    try manager.removeItem(at: backup)
                }
                try manager.moveItem(at: url, to: backup)
            }
        }
        if !manager.fileExists(atPath: url.path) {
            // Create with 0600 before any content is written, independent of umask.
            guard manager.createFile(atPath: url.path, contents: nil, attributes: permissions) else {
                throw CocoaError(.fileWriteUnknown)
            }
        }

        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
    }
}
