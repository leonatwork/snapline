import Foundation
import Testing
@testable import Snapline

@Suite struct DebugLogFileTests {
    @Test func createsPrivateFileAndAppends() throws {
        try withLog { logger, url in
            try logger.append(Data("first\n".utf8))
            #expect(try permissions(of: url) == 0o600)
            try logger.append(Data("second\n".utf8))
            #expect(try Data(contentsOf: url) == Data("first\nsecond\n".utf8))
            #expect(!FileManager.default.fileExists(atPath: url.path + ".1"))
        }
    }

    @Test func existingFileBecomesPrivateWithoutLosingContent() throws {
        try withLog { logger, url in
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("existing\n".utf8).write(to: url)
            try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
            try logger.append(Data("next\n".utf8))
            #expect(try permissions(of: url) == 0o600)
            #expect(try Data(contentsOf: url) == Data("existing\nnext\n".utf8))
        }
    }

    @Test func rotatesOnlyOnTheWriteAfterExceedingLimitAndReplacesBackup() throws {
        try withLog { logger, url in
            let backup = URL(fileURLWithPath: url.path + ".1")
            let atLimit = Data(repeating: 65, count: 1_000_000)
            try logger.append(atLimit)
            try Data("old backup".utf8).write(to: backup)
            try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
            try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: backup.path)

            // At exactly 1 MB, append without rotating. Only the next write rotates.
            try logger.append(Data("B".utf8))
            #expect(try Data(contentsOf: url) == atLimit + Data("B".utf8))
            #expect(try Data(contentsOf: backup) == Data("old backup".utf8))
            #expect(try permissions(of: backup) == 0o600)
            try logger.append(Data("new\n".utf8))
            #expect(try Data(contentsOf: backup) == atLimit + Data("B".utf8))
            #expect(try Data(contentsOf: url) == Data("new\n".utf8))
            #expect(try permissions(of: url) == 0o600)
            #expect(try permissions(of: backup) == 0o600)

            // A second rotation replaces .1; no .2 or other retained files.
            let nextLog = Data("new\n".utf8) + atLimit
            try logger.append(atLimit)
            try logger.append(Data("latest\n".utf8))
            #expect(try Data(contentsOf: backup) == nextLog)
            #expect(try Data(contentsOf: url) == Data("latest\n".utf8))
            #expect(try FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path).sorted()
                    == ["debug.log", "debug.log.1"])
        }
    }

    @Test func existingOversizedFileIsSecuredBeforeRotation() throws {
        try withLog { logger, url in
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let old = Data(repeating: 65, count: 1_000_001)
            try old.write(to: url)
            try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
            try logger.append(Data("next\n".utf8))
            let backup = URL(fileURLWithPath: url.path + ".1")
            #expect(try Data(contentsOf: backup) == old)
            #expect(try Data(contentsOf: url) == Data("next\n".utf8))
            #expect(try permissions(of: backup) == 0o600)
            #expect(try permissions(of: url) == 0o600)
        }
    }

    private func permissions(of url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return try #require(attributes[.posixPermissions] as? NSNumber).intValue
    }

    private func withLog(_ test: (DebugLogFile, URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Snapline/debug.log")
        try test(DebugLogFile(url: url), url)
    }
}
