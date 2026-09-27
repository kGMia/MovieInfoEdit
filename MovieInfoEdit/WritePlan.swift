import Foundation

struct VideoStamp: Codable, Equatable {
    var size: UInt64
    var modified: Date
    var inode: UInt64

    init(url: URL) throws {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        size = (attrs[.size] as? NSNumber)?.uint64Value ?? 0
        modified = attrs[.modificationDate] as? Date ?? .distantPast
        inode = (attrs[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0
    }
}

struct FileChange: Codable {
    var url: URL
    var before: Data?
    var after: Data
}

struct WritePlan: Identifiable, Codable {
    var id = UUID()
    var original: VideoItem
    var updated: VideoItem
    var changes: [FileChange]
    var sourceNFO: URL?
    var sourceBytes: Data?
    var videoStamp: VideoStamp

    var renamed: Bool { original.fileURL != updated.fileURL }
    var outputNFO: FileChange? { changes.last { $0.url.pathExtension.lowercased() == "nfo" } }
    var fieldChanges: [FieldChange] {
        func fields(_ bytes: Data?) -> [String: String] {
            guard let bytes, let root = (try? XMLDocument(data: bytes, options: .nodeLoadExternalEntitiesNever))?.rootElement() else { return [:] }
            var result: [String: [String]] = [:]
            for case let element as XMLElement in root.children ?? [] {
                let name = element.name ?? ""
                if name == "uniqueid", let provider = element.attribute(forName: "type")?.stringValue {
                    result["uniqueid/" + provider, default: []].append(element.stringValue ?? "")
                } else if name == "set", !element.elements(forName: "name").isEmpty {
                    for tag in ["name", "overview"] {
                        result["set/" + tag] = element.elements(forName: tag).compactMap(\.stringValue)
                    }
                } else {
                    result[name, default: []].append(element.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
                }
            }
            return result.mapValues { $0.joined(separator: " · ") }
        }
        let before = fields(sourceBytes), after = fields(outputNFO?.after)
        return Set(before.keys).union(after.keys).sorted().compactMap { key in
            let old = before[key] ?? "", new = after[key] ?? ""
            return old == new ? nil : FieldChange(id: key, before: old, after: new)
        }
    }
}

struct FieldChange: Identifiable {
    let id: String
    let before: String
    let after: String

    var label: String {
        switch id {
        case "title": return L("Title")
        case "originaltitle": return L("Original Title")
        case "sorttitle": return L("Sort Title")
        case "tagline": return L("Tagline")
        case "outline": return L("Outline")
        case "runtime": return L("Runtime Minutes")
        case "mpaa": return L("Certification")
        case "credits": return L("Writers")
        case "tag": return L("Tags")
        case "set/name": return L("Collection")
        case "set/overview": return L("Collection Overview")
        case "trailer": return L("Trailer")
        case "uniqueid/imdb": return "IMDb ID"
        case "uniqueid/tmdb": return "TMDb ID"
        default: return id
        }
    }
}

struct QueuePreview: Identifiable {
    var id = UUID()
    var isBackupRestore = false
    var plans: [UUID: WritePlan] = [:]
    var order: [UUID] = []
    var errors: [String] = []
}

struct UndoRecord: Identifiable, Codable {
    var id = UUID()
    var date = Date()
    var plan: WritePlan
    // A write-ahead receipt survives an app termination between file writes and session save.
    var completed = false
}
