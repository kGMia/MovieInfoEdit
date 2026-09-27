import Foundation
import AppKit

func L(_ key: String.LocalizationValue) -> String {
    String(localized: key)
}

// MARK: - Models
struct VideoItem: Identifiable, Hashable, Codable {
    var id = UUID(); var fileURL: URL; var addedDate = Date()
    var fileName: String { fileURL.lastPathComponent }
    var baseName: String { fileURL.deletingPathExtension().lastPathComponent }
    var folderURL: URL { fileURL.deletingLastPathComponent() }
}

struct Actor: Identifiable, Codable, Equatable { var id = UUID(); var name: String = ""; var role: String = "" }

/// Optional in NFOData so saved queues from earlier versions leave extended XML untouched.
struct MovieDetails: Codable, Equatable {
    var originalTitle = ""
    var sortTitle = ""
    var tagline = ""
    var outline = ""
    var runtime = ""
    var certification = ""
    var writers = ""
    var tags = ""
    var setName = ""
    var setOverview = ""
    var imdbID = ""
    var tmdbID = ""
    var trailer = ""

    static let textFields: [(tag: String, key: WritableKeyPath<MovieDetails, String>)] = [
        ("originaltitle", \.originalTitle), ("sorttitle", \.sortTitle), ("tagline", \.tagline),
        ("outline", \.outline), ("runtime", \.runtime), ("mpaa", \.certification), ("trailer", \.trailer)
    ]
    static var allKeys: [WritableKeyPath<MovieDetails, String>] {
        textFields.map(\.key) + [\.writers, \.tags, \.setName, \.setOverview, \.imdbID, \.tmdbID]
    }
    static func entries(_ value: String) -> [String] {
        var seen = Set<String>()
        return value.components(separatedBy: CharacterSet(charactersIn: ";；\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }
}

struct NFOData: Codable, Equatable {
    var details: MovieDetails? = nil
    // Persist per-video values in batch drafts; resolve them before making queue snapshots.
    var runtimeByVideoID: [String: String]? = nil
    var title: String = ""; var year: String = ""; var country: String = ""; var studio: String = ""
    var enablePremiered: Bool = false; var premieredDate: Date = Date()
    var genres: [String] = []; var director: String = ""; var actors: [Actor] = []; var plot: String = ""
    var rating: Double = 0.0; var posterURL: URL? = nil; var fanartURLs: [URL] = []; var targetFilename: String = ""
}

struct QueueItem: Identifiable, Codable {
    var id = UUID(); var video: VideoItem; var nfoData: NFOData; var status: QueueStatus = .waiting; var errorMessage: String = ""
    enum QueueStatus: String, Codable { case waiting, processing, success, error }
}

actor DropCollector { var urls: [URL] = []; func add(_ url: URL) { urls.append(url) } }

struct LoadedLocalImage: Identifiable { let id = UUID(); let url: URL; let image: NSImage }
struct ExtractedImage: Identifiable { let id = UUID(); let image: NSImage }

struct ImageOption: Identifiable {
    let id: String
    let url: URL?
    let image: NSImage
    var isExtracted: Bool = false
    var tempId: UUID? = nil
}

let supportedVideoExtensions: Set<String> = ["mp4", "mkv", "mov", "avi", "m4v", "ts", "wmv", "flv", "m2ts", "webm", "iso", "rmvb"]
let supportedImageExtensions: Set<String> = ["jpg", "jpeg", "png", "webp", "tif", "tiff", "heic"]

func isSupportedVideoURL(_ url: URL) -> Bool {
    supportedVideoExtensions.contains(url.pathExtension.lowercased())
}

func isSupportedImageURL(_ url: URL) -> Bool {
    supportedImageExtensions.contains(url.pathExtension.lowercased())
}


extension NFOData {
    func resolvingRuntime(for videoID: UUID) -> NFOData {
        var result = self
        if let runtime = runtimeByVideoID?[videoID.uuidString] {
            if result.details == nil { result.details = MovieDetails() }
            result.details?.runtime = runtime
        }
        result.runtimeByVideoID = nil
        return result
    }
}

func runtimeMinutes(seconds: Double) -> String? {
    guard seconds.isFinite, seconds > 0, seconds / 60 < Double(Int.max) else { return nil }
    return String(max(1, Int((seconds / 60).rounded())))
}
