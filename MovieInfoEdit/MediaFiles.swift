import Foundation
import AppKit
import ImageIO
import AVFoundation

// MARK: - Sandbox Access Manager
class SandboxAccessManager {
    static let shared = SandboxAccessManager()
    struct ActiveAccess {
        let url: URL
        var count: Int
    }

    let bookmarkKey = "SecurityScopedBookmarks"
    let legacyDirectoryBookmarkKey = "DirectoryBookmarks"
    var activeAccesses: [String: ActiveAccess] = [:]

    func key(for url: URL) -> String {
        url.standardizedFileURL.path
    }

    func bookmarks() -> [String: Data] {
        var all = UserDefaults.standard.dictionary(forKey: bookmarkKey) as? [String: Data] ?? [:]
        let legacy = UserDefaults.standard.dictionary(forKey: legacyDirectoryBookmarkKey) as? [String: Data] ?? [:]
        for (key, data) in legacy where all[key] == nil {
            all[key] = data
        }
        return all
    }

    func saveBookmark(_ data: Data, for url: URL) {
        var all = bookmarks()
        all[key(for: url)] = data
        UserDefaults.standard.set(all, forKey: bookmarkKey)
    }

    /// Bookmark any user-selected file or directory so it can be accessed later.
    func bookmarkURL(_ url: URL) {
        let normalized = url.standardizedFileURL
        let started = normalized.startAccessingSecurityScopedResource()
        defer {
            if started {
                normalized.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let data = try normalized.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            saveBookmark(data, for: normalized)
        } catch {}
    }

    /// Bookmark a directory so it can be accessed later (persists across launches)
    func bookmarkDirectory(_ directoryURL: URL) {
        guard directoryURL.hasDirectoryPath || (try? directoryURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { return }
        bookmarkURL(directoryURL)
    }

    /// Bookmark the parent directory of a file URL
    func bookmarkParentDirectory(of fileURL: URL) {
        bookmarkURL(fileURL)
        bookmarkDirectory(fileURL.deletingLastPathComponent())
    }

    /// Resolve persisted paths through the closest bookmark; leave offline paths intact.
    func restoredURL(_ url: URL) -> URL {
        let path = key(for: url)
        let all = bookmarks()
        for parent in all.keys.filter({ path == $0 || path.hasPrefix($0 + "/") }).sorted(by: { $0.count > $1.count }) {
            var stale = false
            guard let bytes = all[parent], let resolved = try? URL(resolvingBookmarkData: bytes, options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale) else { continue }
            if stale { bookmarkURL(resolved) }
            let suffix = String(path.dropFirst(parent.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return suffix.isEmpty ? resolved : resolved.appendingPathComponent(suffix)
        }
        return url
    }

    /// Start accessing an exact file/directory URL or the nearest bookmarked ancestor.
    @discardableResult
    func startAccessing(_ url: URL) -> Bool {
        let requested = url.standardizedFileURL
        let requestedKey = key(for: requested)
        if var active = activeAccesses[requestedKey] {
            active.count += 1
            activeAccesses[requestedKey] = active
            return true
        }

        let allBookmarks = bookmarks()
        let requestedPath = requested.path
        let matchingKeys = allBookmarks.keys
            .filter { requestedPath == $0 || requestedPath.hasPrefix($0 + "/") }
            .sorted { $0.count > $1.count }

        for bookmarkPath in matchingKeys {
            guard let data = allBookmarks[bookmarkPath] else { continue }
            var isStale = false
            if let resolved = try? URL(resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &isStale) {
                if isStale {
                    bookmarkURL(resolved)
                }
                if resolved.startAccessingSecurityScopedResource() {
                    activeAccesses[requestedKey] = ActiveAccess(url: resolved, count: 1)
                    return true
                }
            }
        }

        if requested.startAccessingSecurityScopedResource() {
            activeAccesses[requestedKey] = ActiveAccess(url: requested, count: 1)
            return true
        }

        return false
    }

    func stopAccessing(_ url: URL) {
        let requestedKey = key(for: url)
        guard var active = activeAccesses[requestedKey] else { return }
        if active.count == 1 {
            active.url.stopAccessingSecurityScopedResource()
            activeAccesses.removeValue(forKey: requestedKey)
        } else {
            active.count -= 1
            activeAccesses[requestedKey] = active
        }
    }

    /// Start both sibling-folder access and direct file access. Direct file access is important for sandboxed apps launched outside Xcode.
    @discardableResult
    func startAccessingFileAndParent(for fileURL: URL) -> [URL] {
        let file = fileURL.standardizedFileURL
        let directory = file.deletingLastPathComponent()
        var opened: [URL] = []
        if startAccessing(directory) {
            opened.append(directory)
        }
        if startAccessing(file) {
            opened.append(file)
        }
        return opened
    }

    func stopAccessing(_ urls: [URL]) {
        for url in urls.reversed() {
            stopAccessing(url)
        }
    }

    /// Start accessing the directory containing a file. Returns true if access was granted.
    @discardableResult
    func startAccessing(directoryOf fileURL: URL) -> Bool {
        startAccessing(fileURL.deletingLastPathComponent())
    }

    /// Stop accessing the directory containing a file.
    func stopAccessing(directoryOf fileURL: URL) {
        stopAccessing(fileURL.deletingLastPathComponent())
    }
}

struct LocalArtworkLookup {
    var images: [URL] = []
    var posterURL: URL?
    var fanartURLs: [URL] = []
}

func loadLocalImage(at url: URL) -> NSImage? {
    let access = SandboxAccessManager.shared.startAccessingFileAndParent(for: url)
    defer { SandboxAccessManager.shared.stopAccessing(access) }
    guard let data = try? Data(contentsOf: url) else { return nil }
    return NSImage(data: data)
}

func artworkRank(for url: URL, baseName: String, singleVideoFolder: Bool) -> Int? {
    let stem = url.deletingPathExtension().lastPathComponent.lowercased()
    let base = baseName.lowercased()
    let matchesVideo = stem == base || ["-", "_", "."].contains { stem.hasPrefix(base + $0) }
    let posterWords = ["poster", "cover", "folder"]
    let fanartWords = ["fanart", "backdrop", "background", "landscape"]

    if stem == "\(base)-poster" || stem == "\(base)_poster" || stem == "\(base).poster" {
        return 0
    }
    if singleVideoFolder && posterWords.contains(stem) {
        return 1
    }
    if matchesVideo && posterWords.contains(where: { stem.contains($0) }) {
        return 2
    }
    if stem == base {
        return 3
    }
    // Classify backgrounds before the generic basename match.
    if stem == "\(base)-fanart" || stem == "\(base)_fanart" || stem == "\(base).fanart" {
        return 10
    }
    if matchesVideo && fanartWords.contains(where: { stem.contains($0) }) {
        return 11
    }
    if singleVideoFolder && fanartWords.contains(where: { stem == $0 || stem.hasPrefix($0) }) {
        return 12
    }
    if matchesVideo {
        return 4
    }

    return nil
}

func isPosterArtwork(_ url: URL, baseName: String, singleVideoFolder: Bool) -> Bool {
    guard let rank = artworkRank(for: url, baseName: baseName, singleVideoFolder: singleVideoFolder) else { return false }
    return rank <= 4
}

func isFanartArtwork(_ url: URL, baseName: String, singleVideoFolder: Bool) -> Bool {
    guard let rank = artworkRank(for: url, baseName: baseName, singleVideoFolder: singleVideoFolder) else { return false }
    return rank >= 10 && rank < 20
}

func discoverLocalArtwork(for videoURL: URL) -> LocalArtworkLookup {
    let access = SandboxAccessManager.shared.startAccessingFileAndParent(for: videoURL)
    defer { SandboxAccessManager.shared.stopAccessing(access) }

    let folder = videoURL.deletingLastPathComponent()
    let baseName = videoURL.deletingPathExtension().lastPathComponent
    guard let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
        return LocalArtworkLookup()
    }

    let videoCount = files.filter(isSupportedVideoURL).count
    let singleVideoFolder = videoCount <= 1
    let rankedImages = files
        .filter(isSupportedImageURL)
        .compactMap { url -> (url: URL, rank: Int)? in
            guard let rank = artworkRank(for: url, baseName: baseName, singleVideoFolder: singleVideoFolder) else { return nil }
            return (url, rank)
        }
        .sorted {
            if $0.rank == $1.rank {
                return $0.url.lastPathComponent.localizedStandardCompare($1.url.lastPathComponent) == .orderedAscending
            }
            return $0.rank < $1.rank
        }

    let images = rankedImages.map(\.url)
    let posterURL = images.first { isPosterArtwork($0, baseName: baseName, singleVideoFolder: singleVideoFolder) }
    let fanartURLs = images.filter { isFanartArtwork($0, baseName: baseName, singleVideoFolder: singleVideoFolder) }
    return LocalArtworkLookup(images: images, posterURL: posterURL, fanartURLs: fanartURLs)
}

func findExistingNFOURL(for video: VideoItem) -> URL? {
    let access = SandboxAccessManager.shared.startAccessingFileAndParent(for: video.fileURL)
    defer { SandboxAccessManager.shared.stopAccessing(access) }

    let folder = video.folderURL
    let exact = folder.appendingPathComponent("\(video.baseName).nfo")
    if FileManager.default.fileExists(atPath: exact.path) {
        return exact
    }

    guard let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
        return nil
    }

    let nfoFiles = files.filter { $0.pathExtension.lowercased() == "nfo" }
        .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    if let exactMatch = nfoFiles.first(where: {
        $0.deletingPathExtension().lastPathComponent.caseInsensitiveCompare(video.baseName) == .orderedSame
    }) { return exactMatch }

    // Shared movie.nfo and fuzzy matches are only safe in a single-video folder.
    guard files.filter(isSupportedVideoURL).count == 1 else { return nil }
    if let movieNFO = nfoFiles.first(where: { $0.deletingPathExtension().lastPathComponent.lowercased() == "movie" }) {
        return movieNFO
    }
    let matches = nfoFiles.filter { $0.deletingPathExtension().lastPathComponent.localizedCaseInsensitiveContains(video.baseName) }
    if matches.count == 1 { return matches[0] }
    if nfoFiles.count == 1 { return nfoFiles[0] }

    return nil
}

func resolveLocalArtworkReference(_ value: String?, relativeTo folder: URL) -> URL? {
    guard let rawValue = value?.trimmingCharacters(in: .whitespacesAndNewlines), !rawValue.isEmpty else { return nil }
    let lowercasedValue = rawValue.lowercased()
    if lowercasedValue.hasPrefix("http://") || lowercasedValue.hasPrefix("https://") {
        return nil
    }

    let decoded = rawValue.removingPercentEncoding ?? rawValue
    let directURL: URL
    if let url = URL(string: decoded), url.isFileURL {
        directURL = url
    } else if decoded.hasPrefix("/") {
        directURL = URL(fileURLWithPath: decoded)
    } else {
        directURL = folder.appendingPathComponent(decoded)
    }

    if FileManager.default.fileExists(atPath: directURL.path) {
        return directURL
    }

    let targetName = directURL.lastPathComponent
    guard let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
        return nil
    }
    return files.first { $0.lastPathComponent.caseInsensitiveCompare(targetName) == .orderedSame }
}

func firstText(in element: XMLElement, names: [String]) -> String {
    for name in names {
        if let value = element.elements(forName: name).first?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
            return value
        }
    }
    return ""
}

func parseExistingNFO(for video: VideoItem) -> NFOData? {
    let access = SandboxAccessManager.shared.startAccessingFileAndParent(for: video.fileURL)
    defer { SandboxAccessManager.shared.stopAccessing(access) }

    guard let nfoURL = findExistingNFOURL(for: video),
          let xmlDoc = try? XMLDocument(contentsOf: nfoURL, options: [.nodePreserveWhitespace, .nodeLoadExternalEntitiesNever]),
          let root = xmlDoc.rootElement(), root.name == "movie" else { return nil }

    var nfo = NFOData()
    nfo.title = firstText(in: root, names: ["title", "originaltitle"])
    nfo.year = firstText(in: root, names: ["year"])
    nfo.country = firstText(in: root, names: ["country"])
    nfo.studio = firstText(in: root, names: ["studio"])

    let premieredString = firstText(in: root, names: ["premiered", "releasedate", "dateadded"])
    if !premieredString.isEmpty {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.calendar = Calendar(identifier: .gregorian)
        df.dateFormat = "yyyy-MM-dd"
        if let pDate = df.date(from: String(premieredString.prefix(10))) {
            nfo.enablePremiered = true
            nfo.premieredDate = pDate
            if nfo.year.isEmpty {
                nfo.year = String(Calendar.current.component(.year, from: pDate))
            }
        }
    }

    nfo.details = readMovieDetails(root)
    nfo.director = firstText(in: root, names: ["director"])
    nfo.plot = firstText(in: root, names: ["plot", "outline"])
    if let r = Double(firstText(in: root, names: ["userrating", "rating"])) {
        nfo.rating = min(max(r, 0), 10)
    } else if let ratings = root.elements(forName: "ratings").first {
        for rating in ratings.elements(forName: "rating") {
            if let value = Double(firstText(in: rating, names: ["value"])) {
                nfo.rating = min(max(value, 0), 10)
                break
            }
        }
    }

    nfo.genres = root.elements(forName: "genre").compactMap { $0.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    nfo.actors = root.elements(forName: "actor").compactMap { node in
        let name = firstText(in: node, names: ["name"])
        guard !name.isEmpty else { return nil }
        return Actor(name: name, role: firstText(in: node, names: ["role"]))
    }

    let folder = video.folderURL
    nfo.posterURL = root.elements(forName: "thumb").first { thumb in
        let aspect = thumb.attribute(forName: "aspect")?.stringValue?.lowercased()
        return aspect == nil || aspect == "poster"
    }.flatMap { resolveLocalArtworkReference($0.stringValue, relativeTo: folder) }

    var fanartURLs: [URL] = []
    for fanart in root.elements(forName: "fanart") {
        let thumbs = fanart.elements(forName: "thumb")
        if thumbs.isEmpty {
            if let url = resolveLocalArtworkReference(fanart.stringValue, relativeTo: folder) {
                fanartURLs.append(url)
            }
        } else {
            fanartURLs.append(contentsOf: thumbs.compactMap { resolveLocalArtworkReference($0.stringValue, relativeTo: folder) })
        }
    }
    nfo.fanartURLs = Array(NSOrderedSet(array: fanartURLs).compactMap { $0 as? URL })

    let localArtwork = discoverLocalArtwork(for: video.fileURL)
    if nfo.posterURL == nil {
        nfo.posterURL = localArtwork.posterURL
    }
    if nfo.fanartURLs.isEmpty {
        nfo.fanartURLs = localArtwork.fanartURLs
    }
    return nfo
}

/// Keep absent/unknown XML intact when an editor changes only one extended field.
func readMovieDetails(_ root: XMLElement) -> MovieDetails {
    var details = MovieDetails()
    for field in MovieDetails.textFields { details[keyPath: field.key] = firstText(in: root, names: [field.tag]) }
    details.writers = root.elements(forName: "credits").compactMap(\.stringValue).joined(separator: "; ")
    details.tags = root.elements(forName: "tag").compactMap(\.stringValue).joined(separator: "; ")
    if let collection = root.elements(forName: "set").first {
        details.setName = collection.elements(forName: "name").isEmpty ? (collection.stringValue ?? "") : firstText(in: collection, names: ["name"])
        details.setOverview = firstText(in: collection, names: ["overview"])
    }
    for (type, key) in [("imdb", \MovieDetails.imdbID), ("tmdb", \MovieDetails.tmdbID)] {
        details[keyPath: key] = root.elements(forName: "uniqueid").first {
            $0.attribute(forName: "type")?.stringValue?.lowercased() == type
        }?.stringValue ?? ""
    }
    return details
}

/// ImageIO decodes directly to display size on this actor, never on the UI executor.
/// Cache keys include the file stamp so edits made by other apps are picked up.
actor ArtworkThumbnailLoader {
    static let shared = ArtworkThumbnailLoader()
    private let cache = NSCache<NSString, NSData>()

    init() { cache.totalCostLimit = 32 * 1024 * 1024; cache.countLimit = 96 }

    func thumbnail(at url: URL) -> Data? {
        guard !Task.isCancelled,
              let stamp = try? FileManager.default.attributesOfItem(atPath: url.path) else { return nil }
        let key = "\(url.path)|\((stamp[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0)|\(stamp[.size] as? Int ?? 0)" as NSString
        if let bytes = cache.object(forKey: key) { return bytes as Data }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 512,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary), !Task.isCancelled else { return nil }
        let bytes = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(bytes, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination), !Task.isCancelled else { return nil }
        cache.setObject(bytes, forKey: key, cost: image.width * image.height * 4)
        return bytes as Data
    }
}

func loadArtworkThumbnail(at url: URL) async -> NSImage? {
    let access = SandboxAccessManager.shared.startAccessingFileAndParent(for: url)
    defer { SandboxAccessManager.shared.stopAccessing(access) }
    guard let bytes = await ArtworkThumbnailLoader.shared.thumbnail(at: url), !Task.isCancelled else { return nil }
    return NSImage(data: bytes)
}

func readRuntimeMinutes(at originalURL: URL) async throws -> String {
    let url = SandboxAccessManager.shared.restoredURL(originalURL)
    let access = SandboxAccessManager.shared.startAccessingFileAndParent(for: url)
    defer { SandboxAccessManager.shared.stopAccessing(access) }
    try Task.checkCancellation()
    let duration = try await AVURLAsset(url: url).load(.duration)
    try Task.checkCancellation()
    guard let minutes = runtimeMinutes(seconds: duration.seconds) else {
        throw NFOStore.WriteError(message: L("Runtime Unavailable"))
    }
    return minutes
}
