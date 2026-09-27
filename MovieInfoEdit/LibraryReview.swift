import Foundation

enum LibraryIssue: String, CaseIterable, Identifiable {
    case missingNFO, invalidNFO, missingPoster, missingPlot, missingYear, unavailable, conflict
    var id: String { rawValue }
    var title: String {
        switch self {
        case .missingNFO: L("Missing NFO")
        case .invalidNFO: L("Invalid NFO File")
        case .missingPoster: L("Missing Poster")
        case .missingPlot: L("Missing Plot")
        case .missingYear: L("Missing Year")
        case .unavailable: L("Offline or Unauthorized")
        case .conflict: L("Conflicting Target")
        }
    }
}

enum LibraryReview {
    static func inspect(_ video: VideoItem) -> Set<LibraryIssue> {
        let access = SandboxAccessManager.shared.startAccessingFileAndParent(for: video.fileURL)
        defer { SandboxAccessManager.shared.stopAccessing(access) }
        guard FileManager.default.isReadableFile(atPath: video.fileURL.path),
              (try? FileManager.default.contentsOfDirectory(at: video.folderURL, includingPropertiesForKeys: nil)) != nil else { return [.unavailable] }
        var issues = Set<LibraryIssue>()
        let nfoURL = findExistingNFOURL(for: video)
        let data = parseExistingNFO(for: video)
        if nfoURL == nil { issues.insert(.missingNFO) }
        else if data == nil { issues.insert(.invalidNFO) }
        if data?.plot.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true { issues.insert(.missingPlot) }
        if data?.year.isEmpty ?? true { issues.insert(.missingYear) }
        if (data?.posterURL ?? discoverLocalArtwork(for: video.fileURL).posterURL) == nil { issues.insert(.missingPoster) }
        return issues
    }
}
