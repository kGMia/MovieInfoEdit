import Foundation

struct EditorDraft: Codable {
    var data: NFOData
    var baseline: NFOData
}

struct SessionSnapshot: Codable {
    var version = 1
    var videos: [VideoItem]
    var queue: [QueueItem]
    var drafts: [String: EditorDraft]
    var selectedIDs: Set<UUID>
}

enum SessionStore {
    static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MovieInfoEdit", isDirectory: true)
    }
    static var sessionURL: URL { directory.appendingPathComponent("session.json") }
    static var historyDirectory: URL { directory.appendingPathComponent("History", isDirectory: true) }
    static var artworkDirectory: URL { directory.appendingPathComponent("DraftArtwork", isDirectory: true) }

    static func load(from url: URL = sessionURL) throws -> SessionSnapshot? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let bytes = try Data(contentsOf: url)
        do {
            let snapshot = try JSONDecoder().decode(SessionSnapshot.self, from: bytes)
            guard snapshot.version == 1 else { throw CocoaError(.coderReadCorrupt) }
            return snapshot
        } catch {
            // Preserve a recoverable copy instead of silently replacing an unreadable session.
            try bytes.write(to: url.deletingLastPathComponent().appendingPathComponent("session-unreadable-\(UUID().uuidString).json"), options: .atomic)
            throw error
        }
    }

    static func save(_ snapshot: SessionSnapshot, to url: URL = sessionURL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(snapshot).write(to: url, options: .atomic)
    }

    static func saveRecord(_ record: UndoRecord) throws {
        try FileManager.default.createDirectory(at: historyDirectory, withIntermediateDirectories: true)
        try JSONEncoder().encode(record).write(to: historyDirectory.appendingPathComponent(record.id.uuidString + ".json"), options: .atomic)
    }

    static func loadHistory() throws -> [UndoRecord] {
        guard FileManager.default.fileExists(atPath: historyDirectory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: historyDirectory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .map { try JSONDecoder().decode(UndoRecord.self, from: Data(contentsOf: $0)) }
            .sorted { $0.date > $1.date }
    }

    static func removeRecord(_ record: UndoRecord) throws {
        try FileManager.default.removeItem(at: historyDirectory.appendingPathComponent(record.id.uuidString + ".json"))
    }
}
