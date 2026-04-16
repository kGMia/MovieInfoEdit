import SwiftUI
import UniformTypeIdentifiers
import Combine
import Foundation
import AVFoundation
import Vision
import AppKit
import QuickLook

// MARK: - View Extensions
extension View {
    @ViewBuilder
    func applyGlassEffect() -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular, in: .rect)
        } else {
            self.background(.regularMaterial)
        }
    }
}

// MARK: - Localization Helper
func L(_ key: String.LocalizationValue) -> String {
    String(localized: key)
}

func formatDuration(_ seconds: Double) -> String {
    guard !seconds.isNaN && !seconds.isInfinite else { return "00:00" }
    let h = Int(seconds) / 3600; let m = (Int(seconds) % 3600) / 60; let s = Int(seconds) % 60
    if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) } else { return String(format: "%02d:%02d", m, s) }
}

enum AppTheme: String, CaseIterable {
    case system, light, dark
    var colorScheme: ColorScheme? { switch self { case .system: return nil; case .light: return .light; case .dark: return .dark } }
    var localizedName: String { switch self { case .system: return L("theme.system"); case .light: return L("theme.light"); case .dark: return L("theme.dark") } }
}

// MARK: - Models
struct VideoItem: Identifiable, Hashable {
    let id = UUID(); var fileURL: URL; let addedDate = Date()
    var fileName: String { fileURL.lastPathComponent }
    var baseName: String { fileURL.deletingPathExtension().lastPathComponent }
    var folderURL: URL { fileURL.deletingLastPathComponent() }
}

struct Actor: Identifiable { let id = UUID(); var name: String = ""; var role: String = "" }

struct NFOData {
    var title: String = ""; var year: String = ""; var country: String = ""; var studio: String = ""
    var enablePremiered: Bool = false; var premieredDate: Date = Date()
    var genres: [String] = []; var director: String = ""; var actors: [Actor] = []; var plot: String = ""
    var rating: Double = 0.0; var posterURL: URL? = nil; var fanartURLs: [URL] = []; var targetFilename: String = ""
}

struct QueueItem: Identifiable {
    let id = UUID(); var video: VideoItem; var nfoData: NFOData; var status: QueueStatus = .waiting; var errorMessage: String = ""
    enum QueueStatus: String { case waiting, processing, success, error }
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

// MARK: - Cache Manager
class CacheManager {
    static let shared = CacheManager()
    
    private let cacheFileURL: URL = {
        let fm = FileManager.default
        let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "NFOEditor"
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent(appName, isDirectory: true)
        
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let targetURL = dir.appendingPathComponent("cache.json")
        
        if !fm.fileExists(atPath: targetURL.path) {
            if let pw = getpwuid(getuid()), let homePath = pw.pointee.pw_dir {
                let realHome = String(cString: homePath)
                let legacyURL = URL(fileURLWithPath: "\(realHome)/Library/Application Support/\(appName)/cache.json")
                
                if fm.fileExists(atPath: legacyURL.path) {
                    try? fm.copyItem(at: legacyURL, to: targetURL)
                }
            }
        }
        
        return targetURL
    }()
    
    private var store: [String: [String: Int]] = [:]
    
    private init() { load() }
    
    private func load() {
        guard let data = try? Data(contentsOf: cacheFileURL),
              let decoded = try? JSONDecoder().decode([String: [String: Int]].self, from: data) else { return }
        store = decoded
    }
    
    private func save() {
        if let data = try? JSONEncoder().encode(store) {
            try? data.write(to: cacheFileURL, options: .atomic)
        }
    }
    
    func add(item: String, category: String) {
        guard !item.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        store[category, default: [:]][item, default: 0] += 1
        save()
    }
    
    func getSorted(category: String) -> [String] {
        let cache = store[category] ?? [:]
        return cache.sorted {
            if $0.value == $1.value { return $0.key.localizedStandardCompare($1.key) == .orderedAscending }
            return $0.value > $1.value
        }.map { $0.key }
    }
    
    func clear(category: String? = nil) {
        if let cat = category {
            store.removeValue(forKey: cat)
        } else {
            store.removeAll()
        }
        save()
    }
}


// MARK: - Sandbox Access Manager
class SandboxAccessManager {
    static let shared = SandboxAccessManager()
    private let bookmarkKey = "DirectoryBookmarks"
    private var activeAccesses: [URL: Int] = [:]

    /// Bookmark a directory so it can be accessed later (persists across launches)
    func bookmarkDirectory(_ directoryURL: URL) {
        guard directoryURL.hasDirectoryPath || (try? directoryURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { return }
        do {
            let data = try directoryURL.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            var bookmarks = UserDefaults.standard.dictionary(forKey: bookmarkKey) as? [String: Data] ?? [:]
            bookmarks[directoryURL.path] = data
            UserDefaults.standard.set(bookmarks, forKey: bookmarkKey)
        } catch {}
    }

    /// Bookmark the parent directory of a file URL
    func bookmarkParentDirectory(of fileURL: URL) {
        let dir = fileURL.deletingLastPathComponent()
        bookmarkDirectory(dir)
    }

    /// Start accessing the directory containing a file. Returns true if access was granted.
    @discardableResult
    func startAccessing(directoryOf fileURL: URL) -> Bool {
        let dir = fileURL.deletingLastPathComponent()
        if let count = activeAccesses[dir], count > 0 {
            activeAccesses[dir] = count + 1
            return true
        }
        // Try resolving a stored bookmark
        let bookmarks = UserDefaults.standard.dictionary(forKey: bookmarkKey) as? [String: Data] ?? [:]
        if let data = bookmarks[dir.path] {
            var isStale = false
            if let resolved = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale) {
                if isStale { bookmarkDirectory(dir) }
                if resolved.startAccessingSecurityScopedResource() {
                    activeAccesses[dir] = 1
                    return true
                }
            }
        }
        // Fallback: try accessing the directory directly
        if dir.startAccessingSecurityScopedResource() {
            activeAccesses[dir] = 1
            return true
        }
        return false
    }

    /// Stop accessing the directory containing a file.
    func stopAccessing(directoryOf fileURL: URL) {
        let dir = fileURL.deletingLastPathComponent()
        guard let count = activeAccesses[dir], count > 0 else { return }
        if count == 1 {
            dir.stopAccessingSecurityScopedResource()
            activeAccesses.removeValue(forKey: dir)
        } else {
            activeAccesses[dir] = count - 1
        }
    }
}

// MARK: - App State
@Observable class AppState {
    var importedVideos: [VideoItem] = []; var queue: [QueueItem] = []
    var thumbnailsCache: [URL: NSImage] = [:]; var durationsCache: [URL: Double] = [:]
    enum SortOption { case added, name }
    var sortOption: SortOption = .added
    
    func toggleSort() { sortOption = sortOption == .added ? .name : .added; applySort() }
    private func applySort() { if sortOption == .name { importedVideos.sort { $0.fileName.localizedStandardCompare($1.fileName) == .orderedAscending } } else { importedVideos.sort { $0.addedDate < $1.addedDate } } }

    func importFiles(urls: [URL]) {
        let supportedExts = ["mp4", "mkv", "mov", "avi", "m4v", "ts", "wmv", "flv", "m2ts", "webm", "iso", "rmvb"]
        var bookmarkedDirs = Set<URL>()
        for url in urls {
            if supportedExts.contains(url.pathExtension.lowercased()) {
                if !importedVideos.contains(where: { $0.fileURL == url }) { importedVideos.append(VideoItem(fileURL: url)) }
                let dir = url.deletingLastPathComponent()
                if !bookmarkedDirs.contains(dir) { SandboxAccessManager.shared.bookmarkParentDirectory(of: url); bookmarkedDirs.insert(dir) }
            }
        }
        applySort()
    }

    func addToQueue(videos: [VideoItem], data: NFOData) {
        for video in videos {
            CacheManager.shared.add(item: data.director, category: "director")
            data.genres.forEach { CacheManager.shared.add(item: $0, category: "genre") }
            data.actors.forEach { CacheManager.shared.add(item: $0.name, category: "actor") }
            queue.append(QueueItem(video: video, nfoData: data))
        }
    }

    func processQueue() {
        Task {
            let waitingIDs = queue.filter { $0.status == .waiting }.map { $0.id }
            for id in waitingIDs {
                guard let index = queue.firstIndex(where: { $0.id == id }) else { continue }
                await MainActor.run { queue[index].status = .processing }
                guard let currentIndex = queue.firstIndex(where: { $0.id == id }) else { continue }
                await processItem(at: currentIndex)
            }
        }
    }
    
    // Core Mod 3: OCR depth search parameter support
    func performOCR(on url: URL, times: [Double]) async -> String {
        SandboxAccessManager.shared.startAccessing(directoryOf: url)
        defer { SandboxAccessManager.shared.stopAccessing(directoryOf: url) }
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        
        guard let durationObj = try? await asset.load(.duration) else { return "" }
        let durationSec = durationObj.seconds
        let validTimes = times.filter { $0 < durationSec || durationSec.isNaN }
        var extractedLines = [String]()
        
        for t in validTimes {
            let time = CMTime(seconds: t, preferredTimescale: 600)
            if let (cgImage, _) = try? await generator.image(at: time) {
                let request = VNRecognizeTextRequest()
                request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en", "ja"]
                request.usesLanguageCorrection = true
                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                try? handler.perform([request])
                if let results = request.results {
                    let text = results.compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
                    if !text.isEmpty { extractedLines.append(text) }
                }
            }
        }
        return extractedLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func loadMetadata(for url: URL) async {
        if thumbnailsCache[url] != nil && durationsCache[url] != nil { return }
        SandboxAccessManager.shared.startAccessing(directoryOf: url)
        defer { SandboxAccessManager.shared.stopAccessing(directoryOf: url) }
        let asset = AVURLAsset(url: url)
        do {
            let durationObj = try await asset.load(.duration)
            await MainActor.run { if !durationObj.seconds.isNaN { self.durationsCache[url] = durationObj.seconds } }
            let generator = AVAssetImageGenerator(asset: asset); generator.appliesPreferredTrackTransform = true; generator.maximumSize = CGSize(width: 320, height: 320)
            if let (cgImage, _) = try? await generator.image(at: CMTime(seconds: min(15.0, durationObj.seconds / 2.0), preferredTimescale: 600)) {
                await MainActor.run { self.thumbnailsCache[url] = NSImage(cgImage: cgImage, size: NSZeroSize) }
            }
        } catch {}
    }

    func extractMultipleCovers(from videoURL: URL, times: [Double]) async -> [ExtractedImage] {
        SandboxAccessManager.shared.startAccessing(directoryOf: videoURL)
        defer { SandboxAccessManager.shared.stopAccessing(directoryOf: videoURL) }
        let asset = AVURLAsset(url: videoURL); let generator = AVAssetImageGenerator(asset: asset); generator.appliesPreferredTrackTransform = true; generator.requestedTimeToleranceBefore = .zero; generator.requestedTimeToleranceAfter = .zero
        guard let durationObj = try? await asset.load(.duration) else { return [] }
        var results: [ExtractedImage] = []
        for timeSec in times.filter({ $0 < durationObj.seconds }) {
            if let (cgImage, _) = try? await generator.image(at: CMTime(seconds: timeSec, preferredTimescale: 600)), let faceCropped = smartCropTo2x3(cgImage: cgImage) {
                results.append(ExtractedImage(image: NSImage(cgImage: faceCropped, size: NSZeroSize)))
            }
        }
        return results
    }

    private func xmlEscape(_ string: String) -> String {
        string.replacingOccurrences(of: "&", with: "&amp;")
              .replacingOccurrences(of: "<", with: "&lt;")
              .replacingOccurrences(of: ">", with: "&gt;")
              .replacingOccurrences(of: "\"", with: "&quot;")
              .replacingOccurrences(of: "'", with: "&apos;")
    }

    private func processItem(at index: Int) async {
        let item = queue[index]; var video = item.video; let data = item.nfoData; let fm = FileManager.default
        SandboxAccessManager.shared.startAccessing(directoryOf: video.fileURL)
        defer { SandboxAccessManager.shared.stopAccessing(directoryOf: video.fileURL) }
        if !data.targetFilename.isEmpty && data.targetFilename != video.baseName {
            let newURL = video.folderURL.appendingPathComponent("\(data.targetFilename).\(video.fileURL.pathExtension)")
            do { try fm.moveItem(at: video.fileURL, to: newURL); video.fileURL = newURL; await MainActor.run { if let vIdx = self.importedVideos.firstIndex(where: { $0.id == video.id }) { self.importedVideos[vIdx] = video; self.applySort() } } } catch {}
        }
        var xmlElements: [String] = ["<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\" ?>", "<movie>"]; let finalTitle = data.title.isEmpty ? video.baseName : data.title
        xmlElements.append("    <title>\(xmlEscape(finalTitle))</title>")
        if !data.year.isEmpty { xmlElements.append("    <year>\(xmlEscape(data.year))</year>") }
        if data.enablePremiered { let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"; xmlElements.append("    <premiered>\(df.string(from: data.premieredDate))</premiered>") }
        if data.rating > 0 { xmlElements.append("    <userrating>\(String(format: "%.1f", data.rating))</userrating>") }
        if !data.country.isEmpty { xmlElements.append("    <country>\(xmlEscape(data.country))</country>") }
        if !data.studio.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { xmlElements.append("    <studio>\(xmlEscape(data.studio.trimmingCharacters(in: .whitespacesAndNewlines)))</studio>") }
        if !data.director.isEmpty { xmlElements.append("    <director>\(xmlEscape(data.director))</director>") }
        if !data.plot.isEmpty { xmlElements.append("    <plot>\(xmlEscape(data.plot))</plot>") }
        for genre in data.genres { xmlElements.append("    <genre>\(xmlEscape(genre))</genre>") }
        for actor in data.actors { let cleanName = actor.name.trimmingCharacters(in: .whitespacesAndNewlines); let cleanRole = actor.role.trimmingCharacters(in: .whitespacesAndNewlines); if !cleanName.isEmpty { var actorXml = "    <actor>\n        <name>\(xmlEscape(cleanName))</name>"; if !cleanRole.isEmpty { actorXml += "\n        <role>\(xmlEscape(cleanRole))</role>" }; actorXml += "\n    </actor>"; xmlElements.append(actorXml) } }
        let posterTargetURL = video.folderURL.appendingPathComponent("\(video.baseName)-poster.jpg"); var posterGenerated = false
        if let posterURL = data.posterURL { if posterURL.deletingLastPathComponent().standardized == video.folderURL.standardized { xmlElements.append("    <thumb aspect=\"poster\">\(posterURL.lastPathComponent)</thumb>"); posterGenerated = false } else { try? fm.removeItem(at: posterTargetURL); do { try fm.copyItem(at: posterURL, to: posterTargetURL); posterGenerated = true } catch {} } }
        if posterGenerated { xmlElements.append("    <thumb aspect=\"poster\">\(posterTargetURL.lastPathComponent)</thumb>") }
        if !data.fanartURLs.isEmpty {
            xmlElements.append("    <fanart>")
            for (i, fanartURL) in data.fanartURLs.enumerated() {
                if fanartURL.deletingLastPathComponent().standardized == video.folderURL.standardized { xmlElements.append("        <thumb>\(fanartURL.lastPathComponent)</thumb>") } else { let suffix = i == 0 ? "-fanart" : "-fanart\(i+1)"; let targetURL = video.folderURL.appendingPathComponent("\(video.baseName)\(suffix).\(fanartURL.pathExtension)"); try? fm.removeItem(at: targetURL); do { try fm.copyItem(at: fanartURL, to: targetURL); xmlElements.append("        <thumb>\(targetURL.lastPathComponent)</thumb>") } catch {} }
            }
            xmlElements.append("    </fanart>")
        }
        xmlElements.append("</movie>")
        let finalXML = xmlElements.joined(separator: "\n"); let nfoURL = video.folderURL.appendingPathComponent("\(video.baseName).nfo")
        do { try finalXML.write(to: nfoURL, atomically: true, encoding: .utf8); await MainActor.run { self.queue[index].status = .success } } catch { await MainActor.run { self.queue[index].status = .error; self.queue[index].errorMessage = "写入失败" } }
    }

    private func smartCropTo2x3(cgImage: CGImage) -> CGImage? {
        let width = CGFloat(cgImage.width); let height = CGFloat(cgImage.height); let targetRatio: CGFloat = 2.0 / 3.0; var faceCenter = CGPoint(x: width / 2.0, y: height / 2.0)
        let request = VNDetectFaceRectanglesRequest(); let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([request])
        if let results = request.results, let face = results.first { faceCenter = CGPoint(x: face.boundingBox.midX * width, y: (1.0 - face.boundingBox.midY) * height) } else { return nil }
        var cropWidth: CGFloat; var cropHeight: CGFloat
        if (width / height) > targetRatio { cropHeight = height; cropWidth = height * targetRatio } else { cropWidth = width; cropHeight = width / targetRatio }
        let originX = max(0, min(faceCenter.x - (cropWidth / 2.0), width - cropWidth)); let originY = max(0, min(faceCenter.y - (cropHeight / 2.0), height - cropHeight))
        return cgImage.cropping(to: CGRect(x: originX, y: originY, width: cropWidth, height: cropHeight))
    }
}

// MARK: - Components

struct AmbilightThumbnail: View {
    let image: NSImage?
    var width: CGFloat
    var height: CGFloat
    var isStacked: Bool = false
    
    var body: some View {
        ZStack {
            if let image = image {
                // 1. Ambilight glow layer (reduced radius/scale to prevent clipping on the left edge)
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: width, height: height)
                    .clipped()
                    // Refined to avoid hard clipping "shadow" effect at the DetailView boundary
                    .blur(radius: isStacked ? 18 : 16)
                    .opacity(isStacked ? 0.6 : 0.8)
                    .brightness(0.13)
                    .saturation(1.5)
                    .scaleEffect(isStacked ? 1.05 : 1.1)
                    .offset(y: 2)

                // 2. Clear Original Image Layer
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: width, height: height)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .shadow(color: .black.opacity(0.35), radius: 5, y: 3)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.1), lineWidth: 0.5))
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.secondary.opacity(0.2))
                    .frame(width: width, height: height)
                    .overlay(Image(systemName: "film").foregroundStyle(.secondary))
                    .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
            }
        }
    }
}

struct ThumbnailStack: View {
    let videos: [VideoItem]; let cache: [URL: NSImage]
    var onVideoTap: ((URL) -> Void)? = nil
    @State private var isHovered = false
    @State private var hoveredIndex: Int? = nil
    @State private var tappedIndex: Int? = nil

    var body: some View {
        let count = min(videos.count, 4); let isSingle = count == 1
        let cardW: CGFloat = isSingle ? 160 : 140; let cardH: CGFloat = isSingle ? 100 : 90

        ZStack(alignment: .topLeading) {
            ForEach((0..<count).reversed(), id: \.self) { index in
                let img = cache[videos[index].fileURL]
                let isThisHovered = hoveredIndex == index
                ZStack {
                    AmbilightThumbnail(image: img, width: cardW, height: cardH, isStacked: !isSingle)
                    Group {
                        if #available(macOS 26.0, *) {
                            Image(systemName: "play.fill")
                                .font(.system(size: isSingle ? 14 : 11, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.6))
                                .frame(width: isSingle ? 34 : 26, height: isSingle ? 34 : 26)
                                .glassEffect(.clear.interactive(), in: .circle)
                        } else {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: isSingle ? 30 : 24))
                                .foregroundStyle(.white.opacity(0.7))
                                .shadow(color: .black.opacity(0.3), radius: 3, y: 2)
                        }
                    }
                    .opacity(isThisHovered ? 1 : 0)
                    .scaleEffect(isThisHovered ? 1.0 : 0.6)
                    .allowsHitTesting(false)
                }
                .frame(width: cardW, height: cardH)
                .contentShape(RoundedRectangle(cornerRadius: 6))
                .opacity(!isHovered && index == 3 ? 0 : 1)
                .offset(x: xOffset(index: index, isHovered: isHovered, count: count), y: yOffset(index: index, isHovered: isHovered, count: count))
                .zIndex(isThisHovered ? 10 : Double(4 - index))
                .scaleEffect(tappedIndex == index ? 0.92 : (isThisHovered ? 1.08 : (isHovered && isSingle ? 1.05 : 1.0)), anchor: .center)
                .onHover { h in withAnimation(.easeInOut(duration: 0.2)) { hoveredIndex = h ? index : nil } }
                .onTapGesture {
                    withAnimation(.spring(response: 0.15, dampingFraction: 0.5)) { tappedIndex = index }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.55)) { tappedIndex = nil }
                        onVideoTap?(videos[index].fileURL)
                    }
                }
            }
        }
        .frame(width: 200, height: 115, alignment: .topLeading)
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: isHovered)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: hoveredIndex)
        .onHover { isHovered = $0 }
    }
    
    // Core Mod 2: Physics anchor calculation system
    private func xOffset(index: Int, isHovered: Bool, count: Int) -> CGFloat {
        if count == 1 { return 20 } // Adjusted inward to prevent left-side blur clip
        let baseIndex = min(count - 1, 2)
        let unhoveredX = 36 + CGFloat(baseIndex) * 8
        if !isHovered { return 36 + CGFloat(min(index, 2)) * 8 }
        else {
            let shift = CGFloat((count - 1) - index)
            return unhoveredX - shift * 16
        }
    }
    
    private func yOffset(index: Int, isHovered: Bool, count: Int) -> CGFloat {
        if count == 1 { return 10 }
        let baseIndex = min(count - 1, 2)
        let unhoveredY = 14 + CGFloat(baseIndex) * 3
        if !isHovered { return 14 + CGFloat(min(index, 2)) * 3 }
        else {
            let shift = CGFloat((count - 1) - index)
            return unhoveredY - shift * 6
        }
    }
}

struct VisualEffectHeader: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .titlebar; var blendingMode: NSVisualEffectView.BlendingMode = .withinWindow
    func makeNSView(context: Context) -> NSVisualEffectView { let v = NSVisualEffectView(); v.material = material; v.blendingMode = blendingMode; v.state = .active; return v }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

struct EditorHeaderView: View {
    let selectedVideos: [VideoItem]
    let cache: [URL: NSImage]
    let durationsCache: [URL: Double]
    @Binding var targetFilename: String
    var onVideoTap: ((URL) -> Void)? = nil
    
    private var totalDuration: Double { selectedVideos.compactMap { durationsCache[$0.fileURL] }.reduce(0, +) }

    var body: some View {
        ZStack(alignment: .top) {
            
            // 1. Header Background
            // Cleaned up border logic, ensured no overlapping shadows
            Group {
                if #available(macOS 26.0, *) {
                    Color.white.opacity(0.25)
                        .glassEffect(.regular, in: .rect)
                } else {
                    ZStack {
                        VisualEffectHeader(material: .headerView, blendingMode: .withinWindow)
                        Color.black.opacity(0.02) // Subtle flat tint, avoids shadow buildup
                    }
                }
            }
            .frame(height: 180, alignment: .top)
            .ignoresSafeArea(.all, edges: .top)
            
            // 1.5. Top White Gradient Layer
            LinearGradient(
                colors: [.white, .white.opacity(0)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 48)
            .ignoresSafeArea(.all, edges: .top)

            // 2. Content Layer
            Group {
                HStack(alignment: .center, spacing: 28) {
                    if selectedVideos.isEmpty {
                        ZStack(alignment: .center) {
                            Image(systemName: "square.stack.3d.up")
                                .font(.system(size: 40))
                                .foregroundStyle(.tertiary)
                                .frame(width: 160, height: 100)
                        }
                        .frame(width: 200, height: 115, alignment: .topLeading)
                        
                        VStack(alignment: .leading, spacing: 6) {
                            Text(L("Select to Edit")).font(.headline).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        
                    } else {
                        ThumbnailStack(videos: selectedVideos, cache: cache, onVideoTap: onVideoTap)
                        
                        VStack(alignment: .leading, spacing: 6) {
                            if selectedVideos.count == 1 {
                                Text(L("File Name")).font(.caption).foregroundStyle(.secondary)
                                TextField(L("No Extension"), text: $targetFilename)
                                    .textFieldStyle(.plain)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Color.primary.opacity(0.06))
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.15), lineWidth: 1))
                                    .font(.body)
                            } else {
                                Label("\(L("Selected")) \(selectedVideos.count) \(L("Videos"))", systemImage: "checkmark.circle.fill").font(.headline).foregroundStyle(.primary)
                                Text(selectedVideos.map(\.baseName).joined(separator: "、")).font(.caption).foregroundStyle(.secondary).lineLimit(2).truncationMode(.tail)
                            }
                        }.frame(maxWidth: .infinity, alignment: .topLeading)
                        
                        if totalDuration > 0 {
                            VStack(alignment: .trailing, spacing: 4) {
                                Text(L("Duration")).font(.caption).foregroundStyle(.secondary)
                                Text(formatDuration(totalDuration)).font(.headline).monospacedDigit()
                            }
                            .padding(.leading, 10)
                        }
                    }
                }
                // INCREASED leading padding (was 20, now 32)
                // This ensures the ambilight blur from ThumbnailStack naturally fades
                // before it hits the left edge, preventing the "shadow block" clipping artifact.
                .padding(.leading, 32)
                .padding(.trailing, 20)
                .padding(.top, 46)
                .padding(.bottom, 16)
            }
            .frame(height: 180, alignment: .top)
        }
        // Prevents anything inside the header from casting a shadow OUTSIDE the header (into the sidebar)
        .clipped()
    }
}



@ViewBuilder
private func InteractiveImageCard(image: NSImage, width: CGFloat, height: CGFloat, isHovered: Bool, isSelected: Bool, onHoverChange: @escaping (Bool) -> Void, onAction: @escaping () -> Void) -> some View {
    ZStack(alignment: .center) {
        Image(nsImage: image).resizable().aspectRatio(contentMode: .fill).frame(width: width, height: height).clipShape(RoundedRectangle(cornerRadius: 10)).shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2).overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.accentColor, lineWidth: (isHovered || isSelected) ? 3 : 0))
        if isHovered { Button(isSelected ? L("Remove") : L("Select Cover"), action: onAction).buttonStyle(.glass).transition(.opacity) }
    }.onHover { hover in withAnimation(.easeInOut(duration: 0.2)) { onHoverChange(hover) } }
}

struct GallerySection: View {
    @Binding var nfoData: NFOData; var videoURL: URL?
    @State private var loadedLocalImages: [LoadedLocalImage] = []
    
    var body: some View {
        GroupBox(label: Label(L("Gallery"), systemImage: "photo.on.rectangle").font(.headline)) {
            VStack(alignment: .leading, spacing: 12) { SmartPosterPicker(posterURL: $nfoData.posterURL, videoURL: videoURL, loadedLocalImages: $loadedLocalImages); Divider(); FanartPicker(fanartURLs: $nfoData.fanartURLs, videoURL: videoURL, loadedLocalImages: loadedLocalImages) }.padding(.top, 8)
        }
        // Swift 6 Compatibility
        .onChange(of: videoURL) { oldURL, newURL in loadLocalImages() }
        .onAppear { loadLocalImages() }
    }
    
    private func loadLocalImages() {
        guard let url = videoURL else { loadedLocalImages = []; return }
        let folder = url.deletingLastPathComponent(); let baseName = url.deletingPathExtension().lastPathComponent
        Task {
            SandboxAccessManager.shared.startAccessing(directoryOf: url)
            defer { SandboxAccessManager.shared.stopAccessing(directoryOf: url) }
            if let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) {
                let matchedURLs = files.filter { ["jpg", "jpeg", "png", "webp"].contains($0.pathExtension.lowercased()) && $0.lastPathComponent.contains(baseName) }.sorted { $0.lastPathComponent < $1.lastPathComponent }
                var loaded: [LoadedLocalImage] = []
                for file in matchedURLs { if let data = try? Data(contentsOf: file), let img = NSImage(data: data) { loaded.append(LoadedLocalImage(url: file, image: img)) } }
                await MainActor.run { self.loadedLocalImages = loaded }
            } else { await MainActor.run { self.loadedLocalImages = [] } }
        }
    }
}

struct SmartPosterPicker: View {
    @Binding var posterURL: URL?; let videoURL: URL?; @Binding var loadedLocalImages: [LoadedLocalImage]; @Environment(AppState.self) private var appState
    @State private var extractedImages: [ExtractedImage] = []; @State private var isExtracting = false; @State private var hoveredID: String? = nil; @State private var isSelectingFile = false; @State private var extractionPhase = 0
    @State private var previewSelectedID: String? = nil
    @State private var savedExtractedURLs: [UUID: URL] = [:]
    
    private var sortedOptions: [ImageOption] {
        var options: [ImageOption] = loadedLocalImages.map { ImageOption(id: $0.url.absoluteString, url: $0.url, image: $0.image, isExtracted: false) }
        for ext in extractedImages {
            if let savedURL = savedExtractedURLs[ext.id] { options.append(ImageOption(id: ext.id.uuidString, url: savedURL, image: ext.image, isExtracted: true, tempId: ext.id)) }
            else { options.append(ImageOption(id: ext.id.uuidString, url: nil, image: ext.image, isExtracted: true, tempId: ext.id)) }
        }
        if let purl = posterURL, !options.contains(where: { $0.url == purl }) {
            if let data = try? Data(contentsOf: purl), let img = NSImage(data: data) { options.append(ImageOption(id: purl.absoluteString, url: purl, image: img, isExtracted: false)) }
        }
        let activeID = previewSelectedID ?? (posterURL != nil ? options.first(where: {$0.url == posterURL})?.id : nil)
        return options.sorted { a, b in if a.id == activeID { return true }; if b.id == activeID { return false }; return false }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L("Poster")).foregroundStyle(.secondary).frame(width: 40, alignment: .trailing)
                if let url = posterURL { Text(url.lastPathComponent).font(.caption).foregroundStyle(.primary).lineLimit(1) } else { Text(L("Not Selected")).font(.caption).foregroundStyle(.tertiary) }; Spacer()
                Button(action: startSmartExtraction) { if isExtracting { ProgressView().controlSize(.small) } else { Label(extractionPhase == 0 ? L("Auto Extract Covers") : L("Extract More"), systemImage: "sparkles") } }.buttonStyle(.glass).controlSize(.small).disabled(isExtracting || videoURL == nil)
                Button(L("Choose")) { isSelectingFile = true }.buttonStyle(.borderless)
                if posterURL != nil { Button(L("Remove")) { removePoster() }.foregroundStyle(.red).buttonStyle(.borderless) }
            }
            if !sortedOptions.isEmpty {
                let isAnySelected = posterURL != nil
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: isAnySelected ? -100 : 16) {
                        ForEach(Array(sortedOptions.enumerated()), id: \.element.id) { index, option in
                            let isSelected = posterURL != nil && option.url == posterURL
                            let isAnimatingToSelect = previewSelectedID == option.id
                            InteractiveImageCard(image: option.image, width: 100, height: 150, isHovered: hoveredID == option.id, isSelected: isSelected || isAnimatingToSelect, onHoverChange: { hover in hoveredID = hover ? option.id : nil }) {
                                if isSelected {
                                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { removePoster() }
                                } else {
                                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { previewSelectedID = option.id }
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                                            if option.isExtracted { saveImageAsPoster(option) } else { posterURL = option.url }
                                            previewSelectedID = nil
                                        }
                                    }
                                }
                            }.zIndex(isSelected || isAnimatingToSelect ? 10 : 1).scaleEffect(isAnySelected && !isSelected ? 0.5 : 1.0).opacity(isAnySelected && !isSelected ? 0 : 1)
                            // Core Mod 4: Cascade animation
                            .transition(.asymmetric(
                                insertion: .scale(scale: 0.5).combined(with: .opacity).animation(.spring(response: 0.4, dampingFraction: 0.6).delay(Double(index) * 0.05)),
                                removal: .opacity
                            ))
                        }
                    }.padding(.vertical, 8).padding(.horizontal, 4).animation(.spring(response: 0.4, dampingFraction: 0.7), value: posterURL)
                }.frame(height: 170)
            }
        }
        .fileImporter(isPresented: $isSelectingFile, allowedContentTypes: [.image], allowsMultipleSelection: false) { result in if case .success(let urls) = result { posterURL = urls.first } }
        .onChange(of: videoURL) { oldURL, newURL in extractedImages = []; extractionPhase = 0; savedExtractedURLs.removeAll() }
    }

    private func startSmartExtraction() {
        guard let url = videoURL else { return }; isExtracting = true
        let times: [Double] = extractionPhase == 0 ? [5.0, 10.0, 15.0, 20.0, 30.0, 45.0, 60.0] : [90.0 + Double(extractionPhase - 1) * 120.0, 120.0 + Double(extractionPhase - 1) * 120.0, 180.0 + Double(extractionPhase - 1) * 120.0, 300.0 + Double(extractionPhase - 1) * 120.0]
        Task {
            let images = await appState.extractMultipleCovers(from: url, times: times)
            await MainActor.run { if extractionPhase == 0 { self.extractedImages = images } else { self.extractedImages.append(contentsOf: images) }; self.isExtracting = false; self.extractionPhase += 1 }
        }
    }

    private func saveImageAsPoster(_ option: ImageOption) {
        guard let videoURL = videoURL else { return }; let destURL = videoURL.deletingLastPathComponent().appendingPathComponent("\(videoURL.deletingPathExtension().lastPathComponent)-poster.jpg")
        guard let cgImage = option.image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        if let data = NSBitmapImageRep(cgImage: cgImage).representation(using: .jpeg, properties: [.compressionFactor: 0.85]) {
            try? data.write(to: destURL); if let tempId = option.tempId { savedExtractedURLs[tempId] = destURL }; self.posterURL = destURL
            if let idx = loadedLocalImages.firstIndex(where: { $0.url == destURL }) { loadedLocalImages[idx] = LoadedLocalImage(url: destURL, image: option.image) } else { loadedLocalImages.append(LoadedLocalImage(url: destURL, image: option.image)) }
            withAnimation { extractedImages.removeAll(where: { $0.id == option.tempId }) }
        }
    }

    private func removePoster() {
        if let url = posterURL, savedExtractedURLs.values.contains(url) {
            try? FileManager.default.removeItem(at: url)
            loadedLocalImages.removeAll { $0.url == url }
            savedExtractedURLs = savedExtractedURLs.filter { $0.value != url }
        }
        posterURL = nil
    }
}

struct FanartPicker: View {
    @Binding var fanartURLs: [URL]; let videoURL: URL?; let loadedLocalImages: [LoadedLocalImage]
    @State private var isSelecting = false; @State private var hoveredID: String? = nil
    
    private var sortedOptions: [ImageOption] {
        var options: [ImageOption] = loadedLocalImages.map { ImageOption(id: $0.url.absoluteString, url: $0.url, image: $0.image, isExtracted: false) }
        for url in fanartURLs { if !options.contains(where: { $0.url == url }) { if let data = try? Data(contentsOf: url), let img = NSImage(data: data) { options.append(ImageOption(id: url.absoluteString, url: url, image: img, isExtracted: false)) } } }
        return options.sorted { a, b in
            let aSel = a.url != nil && fanartURLs.contains(a.url!); let bSel = b.url != nil && fanartURLs.contains(b.url!)
            if aSel && !bSel { return true }; if !aSel && bSel { return false }; return false
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L("Fanart")).foregroundStyle(.secondary).frame(width: 40, alignment: .trailing)
                Text(fanartURLs.isEmpty ? L("Not Selected") : "\(fanartURLs.count) \(L("Selected N Images"))").foregroundStyle(fanartURLs.isEmpty ? .secondary : .primary); Spacer()
                Button(L("Choose")) { isSelecting = true }; if !fanartURLs.isEmpty { Button(L("Remove")) { fanartURLs.removeAll() }.foregroundStyle(.red).buttonStyle(.borderless) }
            }
            if !sortedOptions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(sortedOptions) { option in
                            let isSelected = option.url.map { fanartURLs.contains($0) } ?? false
                            InteractiveImageCard(image: option.image, width: 160, height: 90, isHovered: hoveredID == option.id, isSelected: isSelected, onHoverChange: { hover in hoveredID = hover ? option.id : nil }) {
                                if isSelected { fanartURLs.removeAll { $0 == option.url } } else if let url = option.url { fanartURLs.append(url) }
                            }.zIndex(isSelected ? 10 : 1)
                        }
                    }.padding(.vertical, 8).padding(.horizontal, 4).animation(.spring(response: 0.4, dampingFraction: 0.7), value: fanartURLs)
                }.frame(height: 110)
            }
        }
        .fileImporter(isPresented: $isSelecting, allowedContentTypes: [.image], allowsMultipleSelection: true) { result in if case .success(let urls) = result { let newURLs = urls.filter { !fanartURLs.contains($0) }; fanartURLs.append(contentsOf: newURLs) } }
    }
}

struct LabeledTextField: View {
    let label: String; @Binding var text: String
    var body: some View { HStack(spacing: 12) { Text(label).foregroundStyle(.secondary).frame(width: 50, alignment: .trailing); TextField(label, text: $text).textFieldStyle(.roundedBorder) } }
}

struct DirectorField: View {
    @Binding var director: String; private var cachedDirectors: [String] { Array(CacheManager.shared.getSorted(category: "director").prefix(10)) }
    @Namespace private var tagAnimation
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            LabeledTextField(label: L("Director"), text: $director)
            if !cachedDirectors.isEmpty {
                HStack(alignment: .center, spacing: 12) { Color.clear.frame(width: 50); ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 6) { ForEach(cachedDirectors, id: \.self) { name in ChipButton(title: name) { withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { director = name } }.matchedGeometryEffect(id: name, in: tagAnimation) } }.padding(.vertical, 8).padding(.horizontal, 2) } }
            }
        }
    }
}

struct ActiveTag: View {
    let title: String; let onRemove: () -> Void; @State private var isHovered = false
    var body: some View { HStack(spacing: 4) { Text(title).font(.subheadline); Button(action: onRemove) { Image(systemName: "xmark.circle.fill").font(.caption) }.buttonStyle(.plain) }.padding(.horizontal, 10).padding(.vertical, 4).background(Color.accentColor.opacity(isHovered ? 0.3 : 0.12)).clipShape(Capsule()).scaleEffect(isHovered ? 1.05 : 1.0).animation(.spring(response: 0.25, dampingFraction: 0.7), value: isHovered).onHover { isHovered = $0 } }
}

struct GenreField: View {
    @Binding var genres: [String]; @Binding var currentInput: String
    @Namespace private var tagAnimation
    private var suggestions: [String] { Array(CacheManager.shared.getSorted(category: "genre").filter { !genres.contains($0) }.prefix(30)) }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) { Text(L("Genres")).foregroundStyle(.secondary).frame(width: 50, alignment: .trailing); TextField(L("Add Genre Hint"), text: $currentInput).textFieldStyle(.roundedBorder).onSubmit { let t = currentInput.trimmingCharacters(in: .whitespacesAndNewlines); if !t.isEmpty && !genres.contains(t) { withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { genres.append(t) } }; currentInput = "" } }
            if !genres.isEmpty { HStack(alignment: .center, spacing: 12) { Color.clear.frame(width: 50); ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 6) { ForEach(genres, id: \.self) { genre in ActiveTag(title: genre) { withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { genres.removeAll { $0 == genre } } }.matchedGeometryEffect(id: genre, in: tagAnimation) } }.padding(.vertical, 8).padding(.horizontal, 2) } } }
            if !suggestions.isEmpty {
                HStack(alignment: .top, spacing: 12) {
                    Text(L("Quick Add")).font(.caption).foregroundStyle(.secondary).frame(width: 50, alignment: .trailing).padding(.top, 4)
                    ScrollView(.horizontal, showsIndicators: false) { VStack(alignment: .leading, spacing: 6) { HStack(spacing: 6) { ForEach(suggestions.prefix(15), id: \.self) { g in ChipButton(title: g) { withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { genres.append(g) } }.matchedGeometryEffect(id: g, in: tagAnimation) } }; if suggestions.count > 15 { HStack(spacing: 6) { ForEach(Array(suggestions.dropFirst(15)), id: \.self) { g in ChipButton(title: g) { withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { genres.append(g) } }.matchedGeometryEffect(id: g, in: tagAnimation) } } } }.padding(.vertical, 8).padding(.horizontal, 2) }
                }
            }
        }
    }
}

struct ActorRow: View {
    @Binding var actor: Actor; let onDelete: () -> Void
    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) { Text(L("Actor Name")).foregroundStyle(.secondary).frame(width: 40, alignment: .trailing); TextField(L("Actor Name PH"), text: $actor.name).textFieldStyle(.roundedBorder); Menu { ForEach(Array(CacheManager.shared.getSorted(category: "actor").prefix(10)), id: \.self) { ca in Button(ca) { actor.name = ca } } } label: { Image(systemName: "clock.arrow.circlepath").foregroundStyle(.secondary) }.menuStyle(.borderlessButton).frame(width: 28); Button(action: onDelete) { Image(systemName: "minus.circle.fill").foregroundStyle(.red) }.buttonStyle(.plain) }
            HStack(spacing: 8) { Text(L("Actor Role")).foregroundStyle(.secondary).frame(width: 40, alignment: .trailing); TextField(L("Actor Role PH"), text: $actor.role).textFieldStyle(.roundedBorder); Menu { Button(L("Lead Male")) { actor.role = L("Lead Male") }; Button(L("Lead Female")) { actor.role = L("Lead Female") }; Button(L("Supporting")) { actor.role = L("Supporting") } } label: { Image(systemName: "list.bullet.circle").foregroundStyle(.secondary) }.menuStyle(.borderlessButton).frame(width: 28); Color.clear.frame(width: 28, height: 1) }
        }.padding(10).background(Color(NSColor.controlBackgroundColor)).clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct ChipButton: View {
    let title: String; let action: () -> Void; @State private var isHovered = false
    var body: some View { Button(action: action) { Text(title).font(.caption).padding(.horizontal, 10).padding(.vertical, 4).background(isHovered ? Color.accentColor : Color.secondary.opacity(0.12)).foregroundStyle(isHovered ? Color.white : Color.primary).clipShape(Capsule()).scaleEffect(isHovered ? 1.05 : 1.0).animation(.spring(response: 0.25, dampingFraction: 0.7), value: isHovered) }.buttonStyle(.plain).onHover { hover in isHovered = hover } }
}

struct PillPicker: View {
    @Binding var selection: Int; let queueCount: Int; @Namespace private var animation
    var body: some View { HStack(spacing: 0) { pillButton(title: L("Editor & Import"), tag: 0); pillButton(title: "\(L("Process Queue")) (\(queueCount))", tag: 1) }.padding(4).background(.regularMaterial, in: Capsule()).overlay(Capsule().stroke(Color.primary.opacity(0.1), lineWidth: 0.5)).frame(width: 280) }
    @ViewBuilder private func pillButton(title: String, tag: Int) -> some View { Button { withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { selection = tag } } label: { Text(title).font(.system(size: 13, weight: selection == tag ? .medium : .regular)).foregroundStyle(selection == tag ? .primary : .secondary).frame(maxWidth: .infinity).padding(.vertical, 6).background { if selection == tag { Capsule().fill(Color(NSColor.controlColor)).shadow(color: .black.opacity(0.1), radius: 2, y: 1).matchedGeometryEffect(id: "ACTIVETAB", in: animation) } }.contentShape(Capsule()) }.buttonStyle(.plain) }
}

struct EditorDetailView: View {
    @Environment(AppState.self) private var appState; @Binding var selectedVideoIDs: Set<UUID>;
    @State private var nfoTemplate = NFOData(); @State private var currentGenreInput: String = ""; @State private var isOCRExtracting: Bool = false; let addQueueNotifier = NotificationCenter.default.publisher(for: .init("TriggerAddToQueue"))
    let years = Array(1900...Calendar.current.component(.year, from: Date()) + 5).reversed(); let presetCountries = ["China", "Hongkong", "Taiwan", "US", "Japan", "Korean", "UK", "France", "Germany"]
    private var selectedVideos: [VideoItem] { appState.importedVideos.filter { selectedVideoIDs.contains($0.id) } }
    
    // Core Mod 4: Deep track OCR status
    @State private var ocrPhase = 0
    @State private var previewURL: URL?

    var body: some View {
        ZStack(alignment: .top) {
            ScrollView { formContent.padding().padding(.top, 178) }
            // Header rendered naturally in ZStack, without clipping anomalies
            EditorHeaderView(
                selectedVideos: selectedVideos,
                cache: appState.thumbnailsCache,
                durationsCache: appState.durationsCache,
                targetFilename: $nfoTemplate.targetFilename,
                onVideoTap: { url in
                    previewURL = url
                }
            )

            // Floating "Add to Queue" button
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Group {
                        if #available(macOS 26.0, *) {
                            Button { submitToQueue() } label: {
                                Label(L("Add to Queue"), systemImage: "arrow.right.square.fill")
                                    .foregroundStyle(.white)
                            }
                            .glassEffect(.regular.tint(.accentColor).interactive())
                            .controlSize(.large)
                            .disabled(selectedVideoIDs.isEmpty)
                            .keyboardShortcut(.return, modifiers: [.command])
                        } else if #available(macOS 15.0, *) {
                            Button { submitToQueue() } label: {
                                Label(L("Add to Queue"), systemImage: "arrow.right.square.fill")
                            }
                            .buttonStyle(.borderedProminent).buttonBorderShape(.capsule).controlSize(.large)
                            .disabled(selectedVideoIDs.isEmpty)
                            .keyboardShortcut(.return, modifiers: [.command])
                        } else {
                            Button { submitToQueue() } label: {
                                Label(L("Add to Queue"), systemImage: "arrow.right.square.fill")
                                    .padding(.horizontal, 24).padding(.vertical, 8)
                            }
                            .buttonStyle(.borderedProminent).clipShape(Capsule())
                            .disabled(selectedVideoIDs.isEmpty)
                            .keyboardShortcut(.return, modifiers: [.command])
                        }
                    }
                    .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
                }
                .padding(.trailing, 24)
                .padding(.bottom, 20)
            }
        }
        .quickLookPreview($previewURL)
        .onReceive(addQueueNotifier) { _ in submitToQueue() }
        .onChange(of: selectedVideoIDs) { oldSelection, newSelection in
            ocrPhase = 0 // Reset depth search on video change
            handleSelectionChange(newSelection)
        }
    }

    private var formContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            GroupBox(label: Label(L("Basic Info"), systemImage: "info.circle").font(.headline)) {
                VStack(alignment: .leading, spacing: 12) {
                    LabeledTextField(label: L("Title"), text: $nfoTemplate.title)
                    HStack(spacing: 12) { Text(L("Year")).foregroundStyle(.secondary).frame(width: 50, alignment: .trailing); Picker("", selection: $nfoTemplate.year) { Text(L("Leave Empty")).tag(""); ForEach(years, id: \.self) { year in Text(String(year)).tag(String(year)) } }.pickerStyle(.menu).frame(width: 100); Text(L("Country")).foregroundStyle(.secondary).frame(width: 70, alignment: .trailing); Picker("", selection: $nfoTemplate.country) { Text(L("Leave Empty")).tag(""); ForEach(presetCountries, id: \.self) { c in Text(c).tag(c) } }.pickerStyle(.menu).frame(width: 110); Spacer() }
                    HStack(spacing: 12) { Text(L("Premiered")).foregroundStyle(.secondary).frame(width: 50, alignment: .trailing); Toggle("", isOn: $nfoTemplate.enablePremiered).labelsHidden(); if nfoTemplate.enablePremiered { DatePicker("", selection: $nfoTemplate.premieredDate, displayedComponents: .date).labelsHidden().onChange(of: nfoTemplate.premieredDate) { oldDate, newDate in nfoTemplate.year = String(Calendar.current.component(.year, from: newDate)) } } else { Text(L("Not Selected")).font(.caption).foregroundStyle(.tertiary) }; Spacer() }
                    DirectorField(director: $nfoTemplate.director); LabeledTextField(label: L("Studio"), text: $nfoTemplate.studio); GenreField(genres: $nfoTemplate.genres, currentInput: $currentGenreInput)
                }.padding(.top, 8)
            }
            GroupBox(label: Label("\(L("Rating")): \(String(format: "%.1f", nfoTemplate.rating))", systemImage: "star.circle").font(.headline)) { HStack(spacing: 12) { Slider(value: $nfoTemplate.rating, in: 0...10, step: 0.1); if nfoTemplate.rating > 0 { Button(L("Clear Rating")) { nfoTemplate.rating = 0 }.buttonStyle(.borderless).foregroundStyle(.secondary) } }.padding(.top, 8) }
            
            GroupBox(label: HStack {
                Label(L("Plot"), systemImage: "text.alignleft").font(.headline); Spacer()
                Button(action: {
                    guard let video = selectedVideos.first else { return }; isOCRExtracting = true
                    let targetTime: Double
                    if ocrPhase == 0 { targetTime = 0.0 }
                    else if ocrPhase == 1 { targetTime = 5.0 }
                    else { targetTime = 5.0 + Double(ocrPhase - 1) * 10.0 }
                    
                    Task {
                        let text = await appState.performOCR(on: video.fileURL, times: [targetTime])
                        await MainActor.run {
                            if !text.isEmpty { nfoTemplate.plot += (nfoTemplate.plot.isEmpty ? "" : "\n") + text }
                            isOCRExtracting = false
                            ocrPhase += 1
                        }
                    }
                }) {
                    if isOCRExtracting { ProgressView().controlSize(.small) }
                    else { Label(ocrPhase == 0 ? L("OCR") : L("Extract More"), systemImage: "text.viewfinder") }
                }.buttonStyle(.glass).controlSize(.small).disabled(isOCRExtracting || selectedVideos.isEmpty)
            }) { TextEditor(text: $nfoTemplate.plot).frame(minHeight: 90, maxHeight: 160).font(.body).overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.2), lineWidth: 1)).padding(.top, 8) }
            
            GroupBox(label: Label(L("Actors"), systemImage: "person.2").font(.headline)) { VStack(spacing: 8) { ForEach($nfoTemplate.actors) { $actor in ActorRow(actor: $actor) { nfoTemplate.actors.removeAll { $0.id == actor.id } } }; Button { nfoTemplate.actors.append(Actor()) } label: { Label(L("Add Actor"), systemImage: "person.badge.plus") }.buttonStyle(.borderless).padding(.top, 4) }.padding(.top, 8) }
            GallerySection(nfoData: $nfoTemplate, videoURL: selectedVideos.first?.fileURL)
            Color.clear.frame(height: 60)
        }
    }

    private func submitToQueue() { appState.addToQueue(videos: selectedVideos, data: nfoTemplate) }
    private func extractDateFromFileName(_ name: String) -> Date? { guard let regex = try? NSRegularExpression(pattern: "(19|20)\\d{2}[-.]?(0[1-9]|1[0-2])[-.]?(0[1-9]|[12][0-9]|3[01])") else { return nil }; let nsString = name as NSString; let results = regex.matches(in: name, range: NSRange(location: 0, length: nsString.length)); if let match = results.first { var dateStr = nsString.substring(with: match.range); dateStr = dateStr.replacingOccurrences(of: ".", with: "-"); let formatter = DateFormatter(); formatter.dateFormat = dateStr.count == 8 ? "yyyyMMdd" : "yyyy-MM-dd"; return formatter.date(from: dateStr) }; return nil }
    private func handleSelectionChange(_ newSelection: Set<UUID>) {
        Task { for id in newSelection { if let video = appState.importedVideos.first(where: { $0.id == id }) { await appState.loadMetadata(for: video.fileURL) } } }; let validVideos = appState.importedVideos.filter { newSelection.contains($0.id) }
        if validVideos.count == 1, let video = validVideos.first { nfoTemplate = NFOData(); nfoTemplate.targetFilename = video.baseName; if let extractedDate = extractDateFromFileName(video.baseName) { nfoTemplate.enablePremiered = true; nfoTemplate.premieredDate = extractedDate; nfoTemplate.year = String(Calendar.current.component(.year, from: extractedDate)) }; if let parsedNFO = parseExistingNFO(for: video) { mergeSingleNFO(parsedNFO) } } else if validVideos.count > 1 { nfoTemplate = NFOData(); let parsedNFOs = validVideos.compactMap { parseExistingNFO(for: $0) }; if let firstNFO = parsedNFOs.first, parsedNFOs.count == validVideos.count { var common = firstNFO; for nfo in parsedNFOs.dropFirst() { if common.year != nfo.year { common.year = "" }; if common.country != nfo.country { common.country = "" }; if common.studio != nfo.studio { common.studio = "" }; if common.director != nfo.director { common.director = "" }; common.genres = common.genres.filter { nfo.genres.contains($0) }; common.actors = common.actors.filter { a1 in nfo.actors.contains(where: { $0.name == a1.name }) } }; common.title = ""; common.plot = ""; common.rating = 0.0; common.targetFilename = ""; common.enablePremiered = false; common.posterURL = nil; common.fanartURLs = []; nfoTemplate = common } } else { nfoTemplate = NFOData() }
    }
    private func parseExistingNFO(for video: VideoItem) -> NFOData? {
        SandboxAccessManager.shared.startAccessing(directoryOf: video.fileURL)
        defer { SandboxAccessManager.shared.stopAccessing(directoryOf: video.fileURL) }
        let nfoURL = video.folderURL.appendingPathComponent("\(video.baseName).nfo"); guard FileManager.default.fileExists(atPath: nfoURL.path), let xmlDoc = try? XMLDocument(contentsOf: nfoURL, options: []), let root = xmlDoc.rootElement() else { return nil }; var nfo = NFOData(); nfo.title = root.elements(forName: "title").first?.stringValue ?? ""; nfo.year = root.elements(forName: "year").first?.stringValue ?? ""; nfo.country = root.elements(forName: "country").first?.stringValue ?? ""; nfo.studio = root.elements(forName: "studio").first?.stringValue ?? ""; if let pStr = root.elements(forName: "premiered").first?.stringValue { let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"; if let pDate = df.date(from: pStr) { nfo.enablePremiered = true; nfo.premieredDate = pDate } }; nfo.director = root.elements(forName: "director").first?.stringValue ?? ""; nfo.plot = root.elements(forName: "plot").first?.stringValue ?? ""; if let r = Double(root.elements(forName: "userrating").first?.stringValue ?? "") { nfo.rating = r }; nfo.genres = root.elements(forName: "genre").compactMap { $0.stringValue }; nfo.actors = root.elements(forName: "actor").compactMap { node in let name = node.elements(forName: "name").first?.stringValue ?? ""; guard !name.isEmpty else { return nil }; return Actor(name: name, role: node.elements(forName: "role").first?.stringValue ?? "") }; return nfo
    }
    private func mergeSingleNFO(_ nfo: NFOData) { if !nfo.title.isEmpty { nfoTemplate.title = nfo.title }; if !nfo.year.isEmpty { nfoTemplate.year = nfo.year }; if !nfo.country.isEmpty { nfoTemplate.country = nfo.country }; if !nfo.studio.isEmpty { nfoTemplate.studio = nfo.studio }; if nfo.enablePremiered { nfoTemplate.enablePremiered = true; nfoTemplate.premieredDate = nfo.premieredDate }; if !nfo.director.isEmpty { nfoTemplate.director = nfo.director }; if !nfo.plot.isEmpty { nfoTemplate.plot = nfo.plot }; if nfo.rating > 0 { nfoTemplate.rating = nfo.rating }; if !nfo.genres.isEmpty { nfoTemplate.genres = nfo.genres }; if !nfo.actors.isEmpty { nfoTemplate.actors = nfo.actors } }
}

struct QueueView: View {
    @Environment(AppState.self) private var appState;
    var body: some View {
        VStack(spacing: 0) {
            Table(appState.queue) {
                TableColumn(L("Target Video")) { item in Text(item.video.fileName).lineLimit(1).truncationMode(.middle) }; TableColumn(L("Write Title")) { item in Text(item.nfoData.title.isEmpty ? L("Auto Detect") : item.nfoData.title).lineLimit(1).foregroundStyle(item.nfoData.title.isEmpty ? .secondary : .primary) }
                TableColumn(L("Status")) { item in VStack(alignment: .leading, spacing: 2) { Text(statusLabel(item.status)).foregroundStyle(statusColor(item.status)).fontWeight(.medium); if item.status == .error && !item.errorMessage.isEmpty { Text(item.errorMessage).font(.caption2).foregroundStyle(.red) } } }
                TableColumn(L("Actions")) { item in Button { appState.queue.removeAll { $0.id == item.id } } label: { Image(systemName: "trash") }.buttonStyle(.borderless).foregroundStyle(.red).disabled(item.status == .processing) }.width(60)
            }.contextMenu(forSelectionType: QueueItem.ID.self) { items in Button(L("Reveal in Finder")) { let urls = appState.queue.filter { items.contains($0.id) }.map { $0.video.fileURL }; if !urls.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(urls) } }; Divider(); Button(L("Remove Selected Tasks"), role: .destructive) { appState.queue.removeAll { items.contains($0.id) } } }
            Divider()
            HStack {
                Button(L("Clear Done")) { appState.queue.removeAll { $0.status == .success } }.disabled(appState.queue.allSatisfy { $0.status != .success }); Spacer()
                let waiting = appState.queue.filter { $0.status == .waiting }.count; let done = appState.queue.filter { $0.status == .success }.count
                if !appState.queue.isEmpty { Text("\(L("Waiting")) \(waiting) · \(L("Done")) \(done)").font(.caption).foregroundStyle(.secondary) }
                if #available(macOS 15.0, *) { Button { appState.processQueue() } label: { Label(L("Generate NFO"), systemImage: "play.fill") }.buttonStyle(.borderedProminent).buttonBorderShape(.capsule).controlSize(.large).tint(.green).disabled(appState.queue.filter { $0.status == .waiting }.isEmpty).keyboardShortcut(.return, modifiers: [.command, .shift]) } else { Button { appState.processQueue() } label: { Label(L("Generate NFO"), systemImage: "play.fill").padding(.horizontal, 28).padding(.vertical, 8) }.buttonStyle(.borderedProminent).clipShape(Capsule()).tint(.green).disabled(appState.queue.filter { $0.status == .waiting }.isEmpty).keyboardShortcut(.return, modifiers: [.command, .shift]) }
            }.padding(.horizontal, 16).padding(.vertical, 10).background(.bar)
        }
    }
    private func statusLabel(_ status: QueueItem.QueueStatus) -> String { switch status { case .waiting: return L("status.waiting"); case .processing: return L("status.processing"); case .success: return L("status.success"); case .error: return L("status.error") } }
    private func statusColor(_ status: QueueItem.QueueStatus) -> Color { switch status { case .success: return .green; case .error: return .red; case .processing: return .orange; case .waiting: return .secondary } }
}

struct ContentView: View {
    @Environment(AppState.self) private var appState;
    @State private var columnVisibility: NavigationSplitViewVisibility = .all; @State private var selectedVideoIDs = Set<UUID>(); @State private var viewMode: Int = 0; @State private var isImportingVideos = false
    let importNotifier = NotificationCenter.default.publisher(for: .init("TriggerImportVideos"))
    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) { SidebarView(selectedVideoIDs: $selectedVideoIDs, isImportingVideos: $isImportingVideos) } detail: { ZStack(alignment: .top) { if viewMode == 0 { EditorDetailView(selectedVideoIDs: $selectedVideoIDs) } else { QueueView().padding(.top, 64) }; PillPicker(selection: $viewMode, queueCount: appState.queue.count).padding(.top, 14).zIndex(100) }.ignoresSafeArea(.all, edges: .top) }.navigationSplitViewStyle(.balanced).onReceive(importNotifier) { _ in isImportingVideos = true }.frame(minWidth: 1080, minHeight: 720)
    }
}

struct SidebarView: View {
    @Environment(AppState.self) private var appState; @Binding var selectedVideoIDs: Set<UUID>; @Binding var isImportingVideos: Bool; @State private var previewURL: URL?
    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                List(selection: $selectedVideoIDs) { ForEach(appState.importedVideos) { video in Text(video.fileName).lineLimit(2).truncationMode(.middle).tag(video.id).scaleEffect(previewURL == video.fileURL ? 1.05 : 1.0).opacity(previewURL == video.fileURL ? 0.8 : 1.0).animation(.spring(response: 0.3, dampingFraction: 0.6), value: previewURL) }.onDelete { indices in let idsToDelete = indices.map { appState.importedVideos[$0].id }; appState.importedVideos.remove(atOffsets: indices); idsToDelete.forEach { selectedVideoIDs.remove($0) } }; Color.clear.frame(maxWidth: .infinity, minHeight: 600).listRowBackground(Color.clear).contentShape(Rectangle()).onTapGesture { selectedVideoIDs.removeAll() } }.contextMenu(forSelectionType: VideoItem.ID.self) { items in if !items.isEmpty { Button(L("Reveal in Finder")) { let urls = appState.importedVideos.filter { items.contains($0.id) }.map { $0.fileURL }; if !urls.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(urls) } }; Divider(); Button(L("Remove from List"), role: .destructive) { withAnimation { appState.importedVideos.removeAll { items.contains($0.id) }; items.forEach { selectedVideoIDs.remove($0) } } } } }.quickLookPreview($previewURL)
                Button("") { withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { if selectedVideoIDs.count == 1, let id = selectedVideoIDs.first, let video = appState.importedVideos.first(where: { $0.id == id }) { previewURL = video.fileURL } } }.keyboardShortcut(.space, modifiers: []).opacity(0)
                if appState.importedVideos.isEmpty { VStack(spacing: 8) { Image(systemName: "arrow.down.doc").font(.title2).foregroundStyle(.tertiary); Text(L("Drop Videos Here")).font(.caption).foregroundStyle(.tertiary) } }
            }.background(Color.clear.contentShape(Rectangle()).onTapGesture { selectedVideoIDs.removeAll() })
            Divider()
            HStack(spacing: 0) { Button { isImportingVideos = true } label: { Image(systemName: "plus").frame(width: 32, height: 32).contentShape(Rectangle()) }.buttonStyle(.borderless).help(L("Import")); Button { withAnimation { appState.importedVideos.removeAll { selectedVideoIDs.contains($0.id) }; selectedVideoIDs.removeAll() } } label: { Image(systemName: "minus").frame(width: 32, height: 32).contentShape(Rectangle()) }.buttonStyle(.borderless).help(L("Remove Selected")).disabled(selectedVideoIDs.isEmpty); Button { withAnimation { appState.toggleSort() } } label: { Image(systemName: appState.sortOption == .added ? "textformat.abc" : "clock").frame(width: 32, height: 32).contentShape(Rectangle()) }.buttonStyle(.borderless).help(appState.sortOption == .added ? L("Sort by Name") : L("Sort by Added")); Spacer(); if !selectedVideoIDs.isEmpty { Text("\(L("Selected Count")) \(selectedVideoIDs.count)").font(.caption).foregroundStyle(.secondary).padding(.trailing, 8) } }.padding(.horizontal, 8).frame(height: 36).background(.bar)
        }.navigationTitle(L("Import Videos")).frame(minWidth: 220, idealWidth: 260)
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in let collector = DropCollector(); let group = DispatchGroup(); for provider in providers { group.enter(); _ = provider.loadObject(ofClass: URL.self) { url, _ in if let url = url { Task { await collector.add(url); group.leave() } } else { group.leave() } } }; group.notify(queue: .main) { Task { let finalURLs = await collector.urls; appState.importFiles(urls: finalURLs) } }; return true }
        .fileImporter(isPresented: $isImportingVideos, allowedContentTypes: [.audiovisualContent], allowsMultipleSelection: true) { result in if case .success(let urls) = result { appState.importFiles(urls: urls) } }
    }
}

// MARK: - App Language (for in-app override)
enum AppLanguage: String, CaseIterable {
    case system, en, zhHans, zhHant, ja, fr
    var displayName: String {
        switch self {
        case .system: return L("theme.system")
        case .en: return "English"
        case .zhHans: return "简体中文"
        case .zhHant: return "繁體中文"
        case .ja: return "日本語"
        case .fr: return "Français"
        }
    }
    var localeCode: String? {
        switch self {
        case .system: return nil
        case .en: return "en"
        case .zhHans: return "zh-Hans"
        case .zhHant: return "zh-Hant"
        case .ja: return "ja"
        case .fr: return "fr"
        }
    }
}

func applyLanguageOverride(_ lang: AppLanguage) {
    if let code = lang.localeCode {
        UserDefaults.standard.set([code], forKey: "AppleLanguages")
    } else {
        UserDefaults.standard.removeObject(forKey: "AppleLanguages")
    }
}

// MARK: - Setting Views
struct SettingsView: View {
    @AppStorage("appTheme") private var appThemeRaw: String = AppTheme.system.rawValue
    @AppStorage("appLanguage") private var appLanguageRaw: String = AppLanguage.system.rawValue
    private var appThemeBinding: Binding<AppTheme> { Binding(get: { AppTheme(rawValue: appThemeRaw) ?? .system }, set: { appThemeRaw = $0.rawValue }) }
    private var appLanguageBinding: Binding<AppLanguage> { Binding(get: { AppLanguage(rawValue: appLanguageRaw) ?? .system }, set: { appLanguageRaw = $0.rawValue; applyLanguageOverride($0) }) }
    var body: some View { Form { Section { Picker(L("Theme Setting"), selection: appThemeBinding) { ForEach(AppTheme.allCases, id: \.rawValue) { theme in Text(theme.localizedName).tag(theme as AppTheme) } }; Picker(L("App Language"), selection: appLanguageBinding) { ForEach(AppLanguage.allCases, id: \.rawValue) { l in Text(l.displayName).tag(l as AppLanguage) } }; Text(L("Language Restart Hint")).font(.caption).foregroundStyle(.tertiary) } header: { Text(L("Appearance & Lang")).font(.headline) }; Section { Text(L("Cache Hint")).font(.caption).foregroundStyle(.secondary); HStack(spacing: 12) { Button(L("Clear Directors")) { CacheManager.shared.clear(category: "director") }; Button(L("Clear Genres")) { CacheManager.shared.clear(category: "genre") }; Button(L("Clear Actors")) { CacheManager.shared.clear(category: "actor") } }; Button(L("Clear All"), role: .destructive) { CacheManager.shared.clear() } } header: { Text(L("Cache Management")).font(.headline) } }.formStyle(.grouped).padding().frame(width: 480, height: 360) }
}
