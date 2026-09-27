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


// MARK: - App State
@Observable class AppState {
    var importedVideos: [VideoItem] = [] { didSet { scheduleSessionSave() } }
    var queue: [QueueItem] = [] { didSet { scheduleSessionSave() } }
    var drafts: [String: EditorDraft] = [:] { didSet { scheduleSessionSave() } }
    var restoredSelection = Set<UUID>() { didSet { scheduleSessionSave() } }
    var history: [UndoRecord] = []
    var queuePreview: QueuePreview?
    var showingHistory = false
    var editorReloadRevision = 0
    var editorReloadVideoID: UUID?
    var libraryIssues: [UUID: Set<LibraryIssue>] = [:]
    var isCheckingLibrary = false
    @ObservationIgnored var restoringSession = true
    @ObservationIgnored var libraryCheckTask: Task<Void, Never>?
    @ObservationIgnored var sessionSaveTask: Task<Void, Never>?

    init() { restoreSession() }
    var isProcessingQueue = false
    var accessError: String?
    var canProcessQueue: Bool { !isProcessingQueue && queuePreview == nil && queue.contains { $0.status == .waiting } }
    var thumbnailsCache: [URL: NSImage] = [:]; var durationsCache: [URL: Double] = [:]
    enum SortOption { case added, name }
    var sortOption: SortOption = .added
    
    func toggleSort() { sortOption = sortOption == .added ? .name : .added; applySort() }
    private func applySort() { if sortOption == .name { importedVideos.sort { $0.fileName.localizedStandardCompare($1.fileName) == .orderedAscending } } else { importedVideos.sort { $0.addedDate < $1.addedDate } } }

    func importFiles(urls: [URL]) {
        var directoriesToVerify = Set<URL>()
        var knownURLs = Set(importedVideos.map { $0.fileURL.standardizedFileURL })
        var additions: [VideoItem] = []
        for suppliedURL in urls {
            let url = suppliedURL.standardizedFileURL
            let granted = suppliedURL.startAccessingSecurityScopedResource()
            defer { if granted { suppliedURL.stopAccessingSecurityScopedResource() } }
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            if isDirectory {
                SandboxAccessManager.shared.bookmarkDirectory(url)
                let access = SandboxAccessManager.shared.startAccessing(url)
                defer {
                    if access {
                        SandboxAccessManager.shared.stopAccessing(url)
                    }
                }
                let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles, .skipsPackageDescendants], errorHandler: { failedURL, error in
                    self.accessError = failedURL.lastPathComponent + ": " + error.localizedDescription
                    return true
                })
                let videoURLs = enumerator?.compactMap { $0 as? URL }.filter {
                    isSupportedVideoURL($0) && (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
                } ?? []
                for videoURL in videoURLs where knownURLs.insert(videoURL.standardizedFileURL).inserted {
                    additions.append(VideoItem(fileURL: videoURL))
                }
            } else if isSupportedVideoURL(url) {
                SandboxAccessManager.shared.bookmarkParentDirectory(of: url)
                directoriesToVerify.insert(url.deletingLastPathComponent().standardizedFileURL)
                if knownURLs.insert(url).inserted {
                    additions.append(VideoItem(fileURL: url))
                }
            }
        }
        importedVideos.append(contentsOf: additions)
        for directory in directoriesToVerify.sorted(by: { $0.path.localizedStandardCompare($1.path) == .orderedAscending }) {
            requestDirectoryAccessIfNeeded(directory)
        }
        applySort()
        checkLibrary()
    }

    private func canReadDirectory(_ directoryURL: URL) -> Bool {
        let opened = SandboxAccessManager.shared.startAccessing(directoryURL)
        defer {
            if opened {
                SandboxAccessManager.shared.stopAccessing(directoryURL)
            }
        }
        return FileManager.default.isWritableFile(atPath: directoryURL.path) && (try? FileManager.default.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) != nil
    }

    private func requestDirectoryAccessIfNeeded(_ directoryURL: URL) {
        guard !canReadDirectory(directoryURL) else { return }

        let panel = NSOpenPanel()
        panel.title = L("Grant Folder Access")
        panel.message = L("Grant access to this media folder so MovieInfoEdit can read existing .nfo files and artwork next to the selected videos.")
        panel.prompt = L("Grant Access")
        panel.directoryURL = directoryURL
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let grantedURL = panel.url {
            let requested = directoryURL.standardizedFileURL.path
            let granted = grantedURL.standardizedFileURL.path
            guard requested == granted || requested.hasPrefix(granted + "/") else {
                accessError = L("Choose Containing Folder")
                return
            }
            SandboxAccessManager.shared.bookmarkDirectory(grantedURL)
            if !canReadDirectory(directoryURL) { accessError = L("Folder Access Unavailable") }
        } else {
            accessError = L("Folder Access Unavailable")
        }
    }

    func addToQueue(videos: [VideoItem], data: NFOData, baseline: NFOData? = nil) {
        for video in videos {
            CacheManager.shared.add(item: data.director, category: "director")
            data.genres.forEach { CacheManager.shared.add(item: $0, category: "genre") }
            data.actors.forEach { CacheManager.shared.add(item: $0.name, category: "actor") }
            var resolved = data
            if let baseline {
                var original = parseExistingNFO(for: video) ?? NFOData()
                let artwork = discoverLocalArtwork(for: video.fileURL)
                if original.posterURL == nil { original.posterURL = artwork.posterURL }
                if original.fanartURLs.isEmpty { original.fanartURLs = artwork.fanartURLs }
                resolved = data.applyingChanges(from: baseline, to: original)
            }
            resolved.runtimeByVideoID = data.runtimeByVideoID
            resolved = resolved.resolvingRuntime(for: video.id)
            // A pending task is an editable snapshot; avoid duplicate writes for one video.
            if let index = queue.firstIndex(where: { $0.video.id == video.id && $0.status == .waiting }) {
                queue[index].nfoData = resolved
            } else {
                queue.append(QueueItem(video: video, nfoData: resolved))
            }
        }
    }

    func processQueue() {
        guard canProcessQueue else { return }
        var preview = QueuePreview()
        var claimed = Set<String>()
        for item in queue where item.status == .waiting {
            do {
                let video = importedVideos.first { $0.id == item.video.id } ?? item.video
                let plan = try NFOStore.prepare(video: video, data: item.nfoData)
                let destinations = plan.changes.map(\.url) + (plan.renamed ? [plan.updated.fileURL] : [])
                let paths = destinations.map { $0.standardizedFileURL.path.lowercased() }
                guard paths.allSatisfy({ !claimed.contains($0) }) else { throw NFOStore.WriteError(message: L("Queue Target Conflict")) }
                claimed.formUnion(paths)
                preview.order.append(item.id)
                preview.plans[item.id] = plan
            } catch { preview.errors.append(item.video.fileName + ": " + error.localizedDescription) }
        }
        queuePreview = preview
    }

    func previewBackupRestore(_ video: VideoItem) {
        guard !isProcessingQueue else { return }
        do {
            let plan = try NFOStore.prepareBackupRestore(video: video)
            queuePreview = QueuePreview(isBackupRestore: true, plans: [plan.id: plan], order: [plan.id])
        } catch { accessError = error.localizedDescription }
    }

    func confirmQueuePreview() {
        guard !isProcessingQueue, let preview = queuePreview, preview.errors.isEmpty else { return }
        queuePreview = nil
        isProcessingQueue = true
        Task {
            defer { isProcessingQueue = false; saveSessionNow() }
            for id in preview.order {
                let index = queue.firstIndex(where: { $0.id == id && $0.status == .waiting })
                guard (index != nil || preview.isBackupRestore), let plan = preview.plans[id] else { continue }
                if let index { queue[index].status = .processing }
                saveSessionNow()
                await Task.yield()
                var receipt = UndoRecord(plan: plan)
                do {
                    try SessionStore.saveRecord(receipt)
                    history.insert(receipt, at: 0)
                    let updated = try NFOStore.commit(plan)
                    receipt.completed = true
                    if let historyIndex = history.firstIndex(where: { $0.id == receipt.id }) { history[historyIndex] = receipt }
                    // The write-ahead receipt is already durable even if this metadata update fails.
                    do { try SessionStore.saveRecord(receipt) } catch { accessError = error.localizedDescription }
                    if let videoIndex = importedVideos.firstIndex(where: { $0.id == updated.id }) { importedVideos[videoIndex] = updated; applySort() }
                    if let queueIndex = queue.firstIndex(where: { $0.id == id }) { queue[queueIndex].video = updated; queue[queueIndex].status = .success }
                    libraryIssues.removeValue(forKey: updated.id)
                    // Keep newer editor drafts; the reviewed queue snapshot may be older than them.
                    if preview.isBackupRestore {
                        drafts = drafts.filter { !$0.key.components(separatedBy: ",").contains(updated.id.uuidString) }
                        editorReloadVideoID = updated.id
                        editorReloadRevision += 1
                    }
                } catch {
                    // Keep the receipt for a possible interrupted/partial write; undo checks current bytes.
                    if preview.isBackupRestore { accessError = error.localizedDescription }
                    if let queueIndex = queue.firstIndex(where: { $0.id == id }) { queue[queueIndex].status = .error; queue[queueIndex].errorMessage = error.localizedDescription }
                }
            }
        }
    }

    func retryFailedItems() {
        guard !isProcessingQueue else { return }
        for index in queue.indices where queue[index].status == .error {
            queue[index].status = .waiting
            queue[index].errorMessage = ""
        }
    }

    // Core Mod 3: OCR depth search parameter support
    func performOCR(on url: URL, times: [Double]) async -> String {
        let access = SandboxAccessManager.shared.startAccessingFileAndParent(for: url)
        defer { SandboxAccessManager.shared.stopAccessing(access) }
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
            guard !Task.isCancelled else { break }
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

    private func cacheThumbnail(_ image: NSImage, for url: URL) {
        if thumbnailsCache[url] == nil, thumbnailsCache.count >= 96, let key = thumbnailsCache.keys.first {
            thumbnailsCache.removeValue(forKey: key)
        }
        thumbnailsCache[url] = image
    }

    func loadMetadata(for url: URL) async {
        if thumbnailsCache[url] != nil && durationsCache[url] != nil { return }
        let access = SandboxAccessManager.shared.startAccessingFileAndParent(for: url)
        defer { SandboxAccessManager.shared.stopAccessing(access) }
        if thumbnailsCache[url] == nil, let poster = discoverLocalArtwork(for: url).posterURL,
           let image = await loadArtworkThumbnail(at: poster) { cacheThumbnail(image, for: url) }
        guard !Task.isCancelled else { return }
        let asset = AVURLAsset(url: url)
        do {
            let durationObj = try await asset.load(.duration)
            guard !Task.isCancelled else { return }
            await MainActor.run { if durationObj.seconds.isFinite && durationObj.seconds >= 0 { self.durationsCache[url] = durationObj.seconds } }
            let generator = AVAssetImageGenerator(asset: asset); generator.appliesPreferredTrackTransform = true; generator.maximumSize = CGSize(width: 320, height: 320)
            if let (cgImage, _) = try? await generator.image(at: CMTime(seconds: durationObj.seconds.isFinite ? max(0, min(15.0, durationObj.seconds / 2.0)) : 0, preferredTimescale: 600)) {
                guard !Task.isCancelled else { return }
                cacheThumbnail(NSImage(cgImage: cgImage, size: NSZeroSize), for: url)
            }
        } catch {}
    }

    func extractMultipleCovers(from videoURL: URL, times: [Double]) async -> [ExtractedImage] {
        let access = SandboxAccessManager.shared.startAccessingFileAndParent(for: videoURL)
        defer { SandboxAccessManager.shared.stopAccessing(access) }
        let asset = AVURLAsset(url: videoURL); let generator = AVAssetImageGenerator(asset: asset); generator.appliesPreferredTrackTransform = true; generator.requestedTimeToleranceBefore = .zero; generator.requestedTimeToleranceAfter = .zero
        guard let durationObj = try? await asset.load(.duration) else { return [] }
        var results: [ExtractedImage] = []
        for timeSec in times.filter({ $0 < durationObj.seconds }) {
            guard !Task.isCancelled else { break }
            if let (cgImage, _) = try? await generator.image(at: CMTime(seconds: timeSec, preferredTimescale: 600)), let faceCropped = smartCropTo2x3(cgImage: cgImage) {
                results.append(ExtractedImage(image: NSImage(cgImage: faceCropped, size: NSZeroSize)))
            }
        }
        return results
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
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let image: NSImage?
    var width: CGFloat
    var height: CGFloat
    var isStacked: Bool = false
    
    var body: some View {
        ZStack {
            if let image = image {
                if !reduceTransparency {
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
                }

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

    var body: some View {
        let count = min(videos.count, 4); let isSingle = count == 1
        let cardW: CGFloat = isSingle ? 160 : 140; let cardH: CGFloat = isSingle ? 100 : 90

        ZStack(alignment: .topLeading) {
            ForEach((0..<count).reversed(), id: \.self) { index in
                let img = cache[videos[index].fileURL]
                let isThisHovered = hoveredIndex == index
                Button { onVideoTap?(videos[index].fileURL) } label: {
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
                .scaleEffect(isThisHovered ? 1.08 : (isHovered && isSingle ? 1.05 : 1.0), anchor: .center)
                .onHover { h in withAnimation(.easeInOut(duration: 0.2)) { hoveredIndex = h ? index : nil } }
                }
                .buttonStyle(.plain)
                .disabled(!isHovered && index == 3)
                .accessibilityHidden(!isHovered && index == 3)
                .accessibilityLabel(videos[index].fileName)
                .help(L("Quick Look"))
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

struct EditorHeaderView: View {
    let selectedVideos: [VideoItem]
    let cache: [URL: NSImage]
    let durationsCache: [URL: Double]
    @Binding var targetFilename: String
    var onVideoTap: ((URL) -> Void)? = nil

    private var totalDuration: Double { selectedVideos.compactMap { durationsCache[$0.fileURL] }.reduce(0, +) }

    var body: some View {
        HStack(spacing: 16) {
            ThumbnailStack(videos: selectedVideos, cache: cache, onVideoTap: onVideoTap)
            VStack(alignment: .leading, spacing: 8) {
                if selectedVideos.count == 1 {
                    Text(L("File Name")).font(.caption).foregroundStyle(.secondary)
                    TextField(L("No Extension"), text: $targetFilename)
                        .textFieldStyle(.roundedBorder)
                    Text(selectedVideos.first?.folderURL.path ?? "")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                } else {
                    Label("\(L("Selected")) \(selectedVideos.count) \(L("Videos"))", systemImage: "checkmark.circle.fill").font(.headline)
                    Text(L("Batch Changes Hint")).font(.caption).foregroundStyle(.secondary)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            if totalDuration > 0 {
                VStack(alignment: .trailing, spacing: 4) {
                    Text(L("Duration")).font(.caption).foregroundStyle(.secondary)
                    Text(formatDuration(totalDuration)).monospacedDigit()
                }
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 8)
        .background(.bar)
    }
}

@ViewBuilder
private func InteractiveImageCard(image: NSImage, width: CGFloat, height: CGFloat, isHovered: Bool, isSelected: Bool, onHoverChange: @escaping (Bool) -> Void, onAction: @escaping () -> Void) -> some View {
    ZStack(alignment: .center) {
        Image(nsImage: image).resizable().aspectRatio(contentMode: .fill).frame(width: width, height: height).clipShape(RoundedRectangle(cornerRadius: 10)).shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2).overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.accentColor, lineWidth: (isHovered || isSelected) ? 3 : 0))
        Button(isSelected ? L("Remove") : L("Select Cover"), action: onAction)
            .buttonStyle(.glass).opacity(isHovered ? 1 : 0.8)
            .accessibilityLabel(isSelected ? L("Remove") : L("Select Cover"))
    }.onHover { hover in withAnimation(.easeInOut(duration: 0.2)) { onHoverChange(hover) } }
}

struct GallerySection: View {
    @Binding var nfoData: NFOData; var videoURL: URL?
    @State private var loadedLocalImages: [LoadedLocalImage] = []
    @State private var loadedVideoURL: URL?
    
    var body: some View {
        Section(header: Label(L("Gallery"), systemImage: "photo.on.rectangle").font(.headline)) {
            VStack(alignment: .leading, spacing: 12) { SmartPosterPicker(posterURL: $nfoData.posterURL, videoURL: videoURL, loadedLocalImages: $loadedLocalImages); Divider(); FanartPicker(fanartURLs: $nfoData.fanartURLs, videoURL: videoURL, loadedLocalImages: loadedLocalImages) }.padding(.top, 8)
        }
        .task(id: [videoURL, nfoData.posterURL].compactMap { $0 } + nfoData.fanartURLs) {
            if loadedVideoURL != videoURL { loadedLocalImages = []; loadedVideoURL = videoURL }
            var urls = videoURL.map { discoverLocalArtwork(for: $0).images } ?? []
            for url in [nfoData.posterURL].compactMap({ $0 }) + nfoData.fanartURLs where !urls.contains(url) { urls.append(url) }
            loadedLocalImages.removeAll { !urls.contains($0.url) }
            for url in urls where !loadedLocalImages.contains(where: { $0.url == url }) {
                guard !Task.isCancelled else { return }
                if let image = await loadArtworkThumbnail(at: url) {
                    guard !Task.isCancelled else { return }
                    loadedLocalImages.append(LoadedLocalImage(url: url, image: image))
                }
            }
        }
    }
}

struct SmartPosterPicker: View {
    @Binding var posterURL: URL?; let videoURL: URL?; @Binding var loadedLocalImages: [LoadedLocalImage]; @Environment(AppState.self) private var appState
    @State private var extractedImages: [ExtractedImage] = []; @State private var isExtracting = false; @State private var hoveredID: String? = nil; @State private var isSelectingFile = false; @State private var extractionPhase = 0
    @State private var extractionTask: Task<Void, Never>?
    @State private var previewSelectedID: String? = nil
    @State private var savedExtractedURLs: [UUID: URL] = [:]
    
    private var sortedOptions: [ImageOption] {
        var options: [ImageOption] = loadedLocalImages.filter { !savedExtractedURLs.values.contains($0.url) }.map { ImageOption(id: $0.url.absoluteString, url: $0.url, image: $0.image, isExtracted: false) }
        for ext in extractedImages {
            if let savedURL = savedExtractedURLs[ext.id] { options.append(ImageOption(id: ext.id.uuidString, url: savedURL, image: ext.image, isExtracted: true, tempId: ext.id)) }
            else { options.append(ImageOption(id: ext.id.uuidString, url: nil, image: ext.image, isExtracted: true, tempId: ext.id)) }
        }
        let activeID = previewSelectedID ?? (posterURL != nil ? options.first(where: {$0.url == posterURL})?.id : nil)
        return options.sorted { $0.id == activeID && $1.id != activeID }
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
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 16) {
                        ForEach(sortedOptions) { option in
                            let isSelected = posterURL != nil && option.url == posterURL
                            let isAnimatingToSelect = previewSelectedID == option.id
                            InteractiveImageCard(image: option.image, width: 100, height: 150, isHovered: hoveredID == option.id, isSelected: isSelected || isAnimatingToSelect, onHoverChange: { hover in hoveredID = hover ? option.id : nil }) {
                                if isSelected {
                                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { removePoster() }
                                } else {
                                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { previewSelectedID = option.id }
                                    if option.isExtracted { saveImageAsPoster(option) } else { posterURL = option.url }
                                    previewSelectedID = nil
                                }
                            }
                            .accessibilityLabel(option.url?.lastPathComponent ?? L("Poster"))

                        }
                    }.padding(.vertical, 8).padding(.horizontal, 4).animation(.spring(response: 0.4, dampingFraction: 0.7), value: posterURL)
                }.frame(height: 170)
            }
        }
        .fileImporter(isPresented: $isSelectingFile, allowedContentTypes: [.image], allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first {
                SandboxAccessManager.shared.bookmarkParentDirectory(of: url)
                posterURL = url
            }
        }
        .onChange(of: videoURL) { _, _ in
            extractionTask?.cancel()
            extractionTask = nil
            isExtracting = false
            extractedImages = []
            extractionPhase = 0
            previewSelectedID = nil
            savedExtractedURLs.removeAll()
        }
        .onDisappear { extractionTask?.cancel() }
    }

    private func startSmartExtraction() {
        guard let url = videoURL else { return }; isExtracting = true
        let times: [Double] = extractionPhase == 0 ? [5.0, 10.0, 15.0, 20.0, 30.0, 45.0, 60.0] : [90.0 + Double(extractionPhase - 1) * 120.0, 120.0 + Double(extractionPhase - 1) * 120.0, 180.0 + Double(extractionPhase - 1) * 120.0, 300.0 + Double(extractionPhase - 1) * 120.0]
        extractionTask = Task {
            let images = await appState.extractMultipleCovers(from: url, times: times)
            guard !Task.isCancelled, videoURL == url else { return }
            await MainActor.run { if extractionPhase == 0 { self.extractedImages = images } else { self.extractedImages.append(contentsOf: images) }; self.isExtracting = false; self.extractionPhase += 1 }
        }
    }

    private func saveImageAsPoster(_ option: ImageOption) {
        guard let cgImage = option.image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let bytes = NSBitmapImageRep(cgImage: cgImage).representation(using: .jpeg, properties: [.compressionFactor: 0.85]) else { return }
        // Keep staged artwork alive for queued snapshots. Never overwrite a media file on selection.
        let destination = SessionStore.artworkDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
        do {
            try FileManager.default.createDirectory(at: SessionStore.artworkDirectory, withIntermediateDirectories: true)
            try bytes.write(to: destination, options: .atomic)
            if let id = option.tempId { savedExtractedURLs[id] = destination }
            posterURL = destination
        } catch { appState.accessError = error.localizedDescription }
    }

    private func removePoster() { posterURL = nil }

}

struct FanartPicker: View {
    @Binding var fanartURLs: [URL]; let videoURL: URL?; let loadedLocalImages: [LoadedLocalImage]
    @State private var isSelecting = false; @State private var hoveredID: String? = nil
    
    private var sortedOptions: [ImageOption] {
        let options: [ImageOption] = loadedLocalImages.map { ImageOption(id: $0.url.absoluteString, url: $0.url, image: $0.image, isExtracted: false) }
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
                    LazyHStack(spacing: 16) {
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
        .fileImporter(isPresented: $isSelecting, allowedContentTypes: [.image], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result {
                urls.forEach { SandboxAccessManager.shared.bookmarkParentDirectory(of: $0) }
                let newURLs = urls.filter { !fanartURLs.contains($0) }
                fanartURLs.append(contentsOf: newURLs)
            }
        }
    }
}

/// All editor rows share label and accessory columns, including rows without actions.
private enum EditorMetrics {
    static let labelWidth: CGFloat = 120
    static let accessoryWidth: CGFloat = 104
    static let spacing: CGFloat = 12
}

struct EditorFieldRow<Content: View, Accessory: View>: View {
    let label: String
    @ViewBuilder var content: () -> Content
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: EditorMetrics.spacing) {
            Text(label).foregroundStyle(.secondary)
                .frame(width: EditorMetrics.labelWidth, alignment: .trailing)
            content().frame(maxWidth: .infinity, alignment: .leading)
            accessory().frame(width: EditorMetrics.accessoryWidth, alignment: .trailing)
        }
        .frame(maxWidth: .infinity)
    }
}

struct LabeledTextField: View {
    let label: String
    @Binding var text: String
    var options: [String] = []

    var body: some View {
        EditorFieldRow(label: label) {
            TextField(label, text: $text, axis: .vertical)
                .labelsHidden().textFieldStyle(.roundedBorder).lineLimit(1...3)
        } accessory: {
            if !options.isEmpty {
                Menu {
                    Button(L("Leave Empty")) { text = "" }
                    Divider()
                    ForEach(options, id: \.self) { value in
                        Button(value) { text = value }
                    }
                } label: { Text(L("Common Options")) }
                .menuStyle(.borderlessButton)
                .help(label + " · " + L("Common Options"))
                .accessibilityLabel(label + " · " + L("Common Options"))
            } else {
                Color.clear.frame(height: 1).accessibilityHidden(true)
            }
        }
    }
}

struct DirectorField: View {
    @Binding var director: String; private var cachedDirectors: [String] { Array(CacheManager.shared.getSorted(category: "director").prefix(10)) }
    @Namespace private var tagAnimation
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            LabeledTextField(label: L("Director"), text: $director)
            if !cachedDirectors.isEmpty {
                HStack(alignment: .center, spacing: 12) { Color.clear.frame(width: EditorMetrics.labelWidth); ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 6) { ForEach(cachedDirectors, id: \.self) { name in ChipButton(title: name) { withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { director = name } }.matchedGeometryEffect(id: name, in: tagAnimation) } }.padding(.vertical, 8).padding(.horizontal, 2) } }
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
            EditorFieldRow(label: L("Genres")) {
                TextField(L("Add Genre Hint"), text: $currentInput).textFieldStyle(.roundedBorder).onSubmit {
                    let value = currentInput.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !value.isEmpty && !genres.contains(value) { genres.append(value) }
                    currentInput = ""
                }
            } accessory: { Color.clear.frame(height: 1).accessibilityHidden(true) }

            if !genres.isEmpty { HStack(alignment: .center, spacing: 12) { Color.clear.frame(width: EditorMetrics.labelWidth); ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 6) { ForEach(genres, id: \.self) { genre in ActiveTag(title: genre) { withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { genres.removeAll { $0 == genre } } }.matchedGeometryEffect(id: genre, in: tagAnimation) } }.padding(.vertical, 8).padding(.horizontal, 2) } } }
            if !suggestions.isEmpty {
                HStack(alignment: .top, spacing: 12) {
                    Text(L("Quick Add")).font(.caption).foregroundStyle(.secondary).frame(width: EditorMetrics.labelWidth, alignment: .trailing).padding(.top, 4)
                    ScrollView(.horizontal, showsIndicators: false) { VStack(alignment: .leading, spacing: 6) { HStack(spacing: 6) { ForEach(suggestions.prefix(15), id: \.self) { g in ChipButton(title: g) { withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { genres.append(g) } }.matchedGeometryEffect(id: g, in: tagAnimation) } }; if suggestions.count > 15 { HStack(spacing: 6) { ForEach(Array(suggestions.dropFirst(15)), id: \.self) { g in ChipButton(title: g) { withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { genres.append(g) } }.matchedGeometryEffect(id: g, in: tagAnimation) } } } }.padding(.vertical, 8).padding(.horizontal, 2) }
                }
            }
        }
    }
}

struct ActorRow: View {
    @Binding var actor: Actor
    let onDelete: () -> Void
    var body: some View {
        VStack(spacing: 8) {
            EditorFieldRow(label: L("Actor Name")) {
                TextField(L("Actor Name PH"), text: $actor.name).textFieldStyle(.roundedBorder)
            } accessory: {
                HStack {
                    Menu {
                        ForEach(Array(CacheManager.shared.getSorted(category: "actor").prefix(10)), id: \.self) { name in
                            Button(name) { actor.name = name }
                        }
                    } label: { Image(systemName: "clock.arrow.circlepath") }
                    .menuStyle(.borderlessButton).help(L("Actor Name"))
                    Button(role: .destructive, action: onDelete) { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless).help(L("Remove"))
                }
            }
            LabeledTextField(label: L("Actor Role"), text: $actor.role,
                             options: [L("Lead Male"), L("Lead Female"), L("Supporting")])
        }.padding(.vertical, 8)
    }
}

struct ChipButton: View {
    let title: String; let action: () -> Void; @State private var isHovered = false
    var body: some View { Button(action: action) { Text(title).font(.caption).padding(.horizontal, 10).padding(.vertical, 4).background(isHovered ? Color.accentColor : Color.secondary.opacity(0.12)).foregroundStyle(isHovered ? Color.white : Color.primary).clipShape(Capsule()).scaleEffect(isHovered ? 1.05 : 1.0).animation(.spring(response: 0.25, dampingFraction: 0.7), value: isHovered) }.buttonStyle(.plain).onHover { hover in isHovered = hover } }
}

struct EditorDetailView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppState.self) private var appState; @Binding var selectedVideoIDs: Set<UUID>;
    @State private var editingIDs = Set<UUID>()
    @State private var selectionBaseline = NFOData()
    @State private var nfoTemplate = NFOData(); @State private var currentGenreInput: String = ""; @State private var isOCRExtracting: Bool = false; let addQueueNotifier = NotificationCenter.default.publisher(for: .init("TriggerAddToQueue"))
    private var selectedVideos: [VideoItem] { appState.importedVideos.filter { selectedVideoIDs.contains($0.id) } }
    
    // Core Mod 4: Deep track OCR status
    @State private var runtimeTask: Task<Void, Never>?
    @State private var isReadingRuntime = false
    private var commonYears: [String] { (1900...(Calendar.current.component(.year, from: Date()) + 2)).reversed().map(String.init) }
    private var commonCountries: [String] {
        [L("China Mainland"), L("Hong Kong"), L("Taiwan"), L("United States"), L("Japan"), L("South Korea"),
         L("United Kingdom"), L("France"), L("Germany"), L("Italy"), L("Spain"), L("Canada"), L("Australia"), L("India"), L("Thailand")]
    }
    @State private var metadataTask: Task<Void, Never>?
    @State private var ocrTask: Task<Void, Never>?
    @State private var ocrPhase = 0
    @State private var previewURL: URL?

    var body: some View {
        Group {
            if selectedVideos.isEmpty {
                ContentUnavailableView(L("Select to Edit"), systemImage: "film.stack",
                                       description: Text(L("Editor Empty Hint")))
            } else {
                formContent
                    .safeAreaInset(edge: .top, spacing: 0) {
                        EditorHeaderView(selectedVideos: selectedVideos, cache: appState.thumbnailsCache,
                                         durationsCache: appState.durationsCache, targetFilename: $nfoTemplate.targetFilename,
                                         onVideoTap: { previewURL = $0 })
                    }
                    .safeAreaInset(edge: .bottom) {
                        HStack {
                            Text("\(selectedVideos.count) \(L("Videos"))").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button(action: submitToQueue) {
                                Label(L("Add to Queue"), systemImage: "text.badge.plus")
                            }
                            .buttonStyle(.glassProminent).controlSize(.large)
                            .disabled(isReadingRuntime)
                            .keyboardShortcut(.return, modifiers: [.command])
                        }.padding(12).background(.bar)
                    }
            }
        }
        .transaction { if reduceMotion { $0.animation = nil; $0.disablesAnimations = true } }
        .scopedQuickLookPreview($previewURL)
        .onReceive(addQueueNotifier) { _ in submitToQueue() }
        .onChange(of: selectedVideoIDs, initial: true) { _, newSelection in
            runtimeTask?.cancel()
            isReadingRuntime = false
            ocrTask?.cancel()
            isOCRExtracting = false
            ocrPhase = 0
            appState.saveDraft(nfoTemplate, baseline: selectionBaseline, ids: editingIDs)
            editingIDs = newSelection
            handleSelectionChange(newSelection)
            if let draft = appState.drafts[AppState.draftKey(newSelection)] {
                let details = nfoTemplate.details
                nfoTemplate = draft.data
                selectionBaseline = draft.baseline
                if nfoTemplate.details == nil { nfoTemplate.details = details }
                if selectionBaseline.details == nil { selectionBaseline.details = details }
            }
        }
        .onChange(of: nfoTemplate) { _, data in appState.saveDraft(data, baseline: selectionBaseline, ids: editingIDs) }
        .onChange(of: appState.editorReloadRevision) { _, _ in
            if let id = appState.editorReloadVideoID, selectedVideoIDs.contains(id) { handleSelectionChange(selectedVideoIDs) }
        }
        .onDisappear { runtimeTask?.cancel(); isReadingRuntime = false; metadataTask?.cancel(); ocrTask?.cancel(); appState.saveDraft(nfoTemplate, baseline: selectionBaseline, ids: editingIDs); appState.saveSessionNow() }
    }

    private var formContent: some View {
        Form {
            Section(header: Label(L("Basic Info"), systemImage: "info.circle").font(.headline)) {
                VStack(alignment: .leading, spacing: 12) {
                    LabeledTextField(label: L("Title"), text: $nfoTemplate.title)
                    LabeledTextField(label: L("Year"), text: $nfoTemplate.year, options: commonYears)
                    LabeledTextField(label: L("Country"), text: $nfoTemplate.country, options: commonCountries)
                    EditorFieldRow(label: L("Premiered")) {
                        Toggle(L("Premiered"), isOn: $nfoTemplate.enablePremiered).labelsHidden()
                    } accessory: { Color.clear.frame(height: 1) }
                    if nfoTemplate.enablePremiered {
                        EditorFieldRow(label: L("Release Date")) {
                            DatePicker(L("Release Date"), selection: $nfoTemplate.premieredDate, displayedComponents: .date)
                                .labelsHidden()
                                .onChange(of: nfoTemplate.premieredDate) { _, date in
                                    nfoTemplate.year = String(Calendar.current.component(.year, from: date))
                                }
                        } accessory: { Color.clear.frame(height: 1) }
                    }
                    DirectorField(director: $nfoTemplate.director); LabeledTextField(label: L("Studio"), text: $nfoTemplate.studio); GenreField(genres: $nfoTemplate.genres, currentInput: $currentGenreInput)
                }.padding(.top, 8)
            }
            Section(L("Extended Metadata")) {
                LabeledTextField(label: L("Original Title"), text: detailBinding(\.originalTitle))
                LabeledTextField(label: L("Sort Title"), text: detailBinding(\.sortTitle))
                LabeledTextField(label: L("Tagline"), text: detailBinding(\.tagline))
                LabeledTextField(label: L("Outline"), text: detailBinding(\.outline))
                EditorFieldRow(label: L("Runtime Minutes")) {
                    TextField(L("Runtime Minutes"), text: detailBinding(\.runtime))
                        .textFieldStyle(.roundedBorder).disabled(isReadingRuntime)
                } accessory: {
                    HStack(spacing: 8) {
                        Button(action: fetchRuntime) {
                            if isReadingRuntime { ProgressView().controlSize(.small) }
                            else { Text(L("Read Runtime")) }
                        }
                            .disabled(isReadingRuntime || selectedVideos.isEmpty)
                            .help(L("Read Runtime Hint"))
                        Button {
                            detailBinding(\.runtime).wrappedValue = ""
                        } label: { Image(systemName: "xmark.circle") }
                        .buttonStyle(.borderless).disabled(isReadingRuntime).help(L("Clear Runtime"))
                    }
                }
                if let values = nfoTemplate.runtimeByVideoID, !values.isEmpty {
                    Text(L("Batch Runtime Ready")).font(.caption).foregroundStyle(.secondary)
                }
                LabeledTextField(label: L("Certification"), text: detailBinding(\.certification),
                                 options: ["G", "PG", "PG-13", "R", "NC-17", "NR", "TV-Y", "TV-G", "TV-PG", "TV-14", "TV-MA"] )
                LabeledTextField(label: L("Writers"), text: detailBinding(\.writers))
                LabeledTextField(label: L("Tags"), text: detailBinding(\.tags))
                Text(L("Multiple Values Hint")).font(.caption).foregroundStyle(.secondary)
            }
            Section(L("Collection and IDs")) {
                LabeledTextField(label: L("Collection"), text: detailBinding(\.setName))
                LabeledTextField(label: L("Collection Overview"), text: detailBinding(\.setOverview))
                LabeledTextField(label: "IMDb ID", text: detailBinding(\.imdbID))
                LabeledTextField(label: "TMDb ID", text: detailBinding(\.tmdbID))
                LabeledTextField(label: L("Trailer"), text: detailBinding(\.trailer))
                Text(L("Metadata IDs Hint")).font(.caption).foregroundStyle(.secondary)
            }
            Section(header: Label("\(L("Rating")): \(String(format: "%.1f", nfoTemplate.rating))", systemImage: "star.circle").font(.headline)) { HStack(spacing: 12) { Slider(value: $nfoTemplate.rating, in: 0...10, step: 0.1); if nfoTemplate.rating > 0 { Button(L("Clear Rating")) { nfoTemplate.rating = 0 }.buttonStyle(.borderless).foregroundStyle(.secondary) } }.padding(.top, 8) }
            
            Section(header: HStack {
                Label(L("Plot"), systemImage: "text.alignleft").font(.headline); Spacer()
                Button(action: {
                    guard let video = selectedVideos.first else { return }; isOCRExtracting = true
                    let targetTime: Double
                    if ocrPhase == 0 { targetTime = 0.0 }
                    else if ocrPhase == 1 { targetTime = 5.0 }
                    else { targetTime = 5.0 + Double(ocrPhase - 1) * 10.0 }
                    
                    let selection = selectedVideoIDs
                    ocrTask = Task {
                        let text = await appState.performOCR(on: video.fileURL, times: [targetTime])
                        guard !Task.isCancelled, selectedVideoIDs == selection else { return }
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
            
            Section(header: Label(L("Actors"), systemImage: "person.2").font(.headline)) { VStack(spacing: 8) { ForEach($nfoTemplate.actors) { $actor in ActorRow(actor: $actor) { nfoTemplate.actors.removeAll { $0.id == actor.id } } }; Button { nfoTemplate.actors.append(Actor()) } label: { Label(L("Add Actor"), systemImage: "person.badge.plus") }.buttonStyle(.borderless).padding(.top, 4) }.padding(.top, 8) }
            GallerySection(nfoData: $nfoTemplate, videoURL: selectedVideos.first?.fileURL)
        }
        .formStyle(.grouped)
    }

    private func detailBinding(_ key: WritableKeyPath<MovieDetails, String>) -> Binding<String> {
        Binding(get: { (nfoTemplate.details ?? MovieDetails())[keyPath: key] }, set: { value in
            var details = nfoTemplate.details ?? MovieDetails()
            details[keyPath: key] = value
            nfoTemplate.details = details
            if key == \MovieDetails.runtime { nfoTemplate.runtimeByVideoID = nil }
        })
    }

    private func fetchRuntime() {
        runtimeTask?.cancel()
        let videos = selectedVideos
        let selection = selectedVideoIDs
        isReadingRuntime = true
        runtimeTask = Task {
            var values: [String: String] = [:]
            do {
                for video in videos {
                    do { values[video.id.uuidString] = try await readRuntimeMinutes(at: video.fileURL) }
                    catch is CancellationError { return }
                    catch { throw NFOStore.WriteError(message: video.fileName + ": " + L("Runtime Unavailable") + "\n" + error.localizedDescription) }
                }
                guard !Task.isCancelled, selectedVideoIDs == selection else { return }
                var details = nfoTemplate.details ?? MovieDetails()
                details.runtime = Set(values.values).count == 1 ? (values.values.first ?? "") : ""
                nfoTemplate.details = details
                nfoTemplate.runtimeByVideoID = videos.count > 1 ? values : nil
            } catch {
                guard !Task.isCancelled, selectedVideoIDs == selection else { return }
                appState.accessError = error.localizedDescription
            }
            if !Task.isCancelled { isReadingRuntime = false }
        }
    }

    private func submitToQueue() { guard !isReadingRuntime else { return }; appState.addToQueue(videos: selectedVideos, data: nfoTemplate, baseline: selectedVideos.count > 1 ? selectionBaseline : nil) }
    private func extractDateFromFileName(_ name: String) -> Date? { guard let regex = try? NSRegularExpression(pattern: "(19|20)\\d{2}[-.]?(0[1-9]|1[0-2])[-.]?(0[1-9]|[12][0-9]|3[01])") else { return nil }; let nsString = name as NSString; let results = regex.matches(in: name, range: NSRange(location: 0, length: nsString.length)); if let match = results.first { var dateStr = nsString.substring(with: match.range); dateStr = dateStr.replacingOccurrences(of: ".", with: "-"); let formatter = DateFormatter(); formatter.dateFormat = dateStr.count == 8 ? "yyyyMMdd" : "yyyy-MM-dd"; return formatter.date(from: dateStr) }; return nil }
    private func handleSelectionChange(_ newSelection: Set<UUID>) {
        runtimeTask?.cancel()
        isReadingRuntime = false
        metadataTask?.cancel()
        let validVideos = appState.importedVideos.filter { newSelection.contains($0.id) }
        metadataTask = Task {
            for video in validVideos {
                guard !Task.isCancelled else { return }
                await appState.loadMetadata(for: video.fileURL)
            }
        }
        if validVideos.count == 1, let video = validVideos.first {
            nfoTemplate = NFOData()
            nfoTemplate.targetFilename = video.baseName
            if let extractedDate = extractDateFromFileName(video.baseName) {
                nfoTemplate.enablePremiered = true
                nfoTemplate.premieredDate = extractedDate
                nfoTemplate.year = String(Calendar.current.component(.year, from: extractedDate))
            }
            if let parsedNFO = parseExistingNFO(for: video) {
                mergeSingleNFO(parsedNFO)
            } else {
                mergeSingleNFO(localArtworkNFO(for: video))
            }
        } else if validVideos.count > 1 {
            nfoTemplate = NFOData()
            let parsedNFOs = validVideos.compactMap { parseExistingNFO(for: $0) }
            if let firstNFO = parsedNFOs.first, parsedNFOs.count == validVideos.count {
                var common = firstNFO
                for nfo in parsedNFOs.dropFirst() {
                    if common.year != nfo.year { common.year = "" }
                    if common.country != nfo.country { common.country = "" }
                    if common.studio != nfo.studio { common.studio = "" }
                    if common.director != nfo.director { common.director = "" }
                    var details = common.details ?? MovieDetails()
                    let other = nfo.details ?? MovieDetails()
                    for key in MovieDetails.allKeys where details[keyPath: key] != other[keyPath: key] { details[keyPath: key] = "" }
                    common.details = details
                    common.genres = common.genres.filter { nfo.genres.contains($0) }
                    common.actors = common.actors.filter { a1 in nfo.actors.contains(where: { $0.name == a1.name && $0.role == a1.role }) }
                }
                common.title = ""
                common.plot = ""
                common.rating = 0.0
                common.targetFilename = ""
                common.enablePremiered = false
                common.posterURL = nil
                common.fanartURLs = []
                nfoTemplate = common
            }
        } else {
            nfoTemplate = NFOData()
        }
        if nfoTemplate.details == nil { nfoTemplate.details = MovieDetails() }
        selectionBaseline = nfoTemplate
    }

    private func localArtworkNFO(for video: VideoItem) -> NFOData {
        let artwork = discoverLocalArtwork(for: video.fileURL)
        var nfo = NFOData()
        nfo.posterURL = artwork.posterURL
        nfo.fanartURLs = artwork.fanartURLs
        return nfo
    }

    private func mergeSingleNFO(_ nfo: NFOData) { nfoTemplate.details = nfo.details; if !nfo.title.isEmpty { nfoTemplate.title = nfo.title }; if !nfo.year.isEmpty { nfoTemplate.year = nfo.year }; if !nfo.country.isEmpty { nfoTemplate.country = nfo.country }; if !nfo.studio.isEmpty { nfoTemplate.studio = nfo.studio }; if nfo.enablePremiered { nfoTemplate.enablePremiered = true; nfoTemplate.premieredDate = nfo.premieredDate }; if !nfo.director.isEmpty { nfoTemplate.director = nfo.director }; if !nfo.plot.isEmpty { nfoTemplate.plot = nfo.plot }; if nfo.rating > 0 { nfoTemplate.rating = nfo.rating }; if !nfo.genres.isEmpty { nfoTemplate.genres = nfo.genres }; if !nfo.actors.isEmpty { nfoTemplate.actors = nfo.actors }; if nfo.posterURL != nil { nfoTemplate.posterURL = nfo.posterURL }; if !nfo.fanartURLs.isEmpty { nfoTemplate.fanartURLs = nfo.fanartURLs } }
}

struct QueueView: View {
    @State private var selection = Set<UUID>()
    @Environment(AppState.self) private var appState;
    var body: some View {
        VStack(spacing: 0) {
            Table(appState.queue, selection: $selection) {
                TableColumn(L("Target Video")) { item in Text(item.video.fileName).lineLimit(1).truncationMode(.middle) }; TableColumn(L("Write Title")) { item in Text(item.nfoData.title.isEmpty ? L("Auto Detect") : item.nfoData.title).lineLimit(1).foregroundStyle(item.nfoData.title.isEmpty ? .secondary : .primary) }
                TableColumn(L("Status")) { item in VStack(alignment: .leading, spacing: 2) { Text(statusLabel(item.status)).foregroundStyle(statusColor(item.status)).fontWeight(.medium); if item.status == .error && !item.errorMessage.isEmpty { Text(item.errorMessage).font(.caption2).foregroundStyle(.red) } } }
                TableColumn(L("Actions")) { item in Button { appState.queue.removeAll { $0.id == item.id } } label: { Image(systemName: "trash") }.buttonStyle(.borderless).foregroundStyle(.red).disabled(item.status == .processing) }.width(60)
            }.contextMenu(forSelectionType: QueueItem.ID.self) { items in Button(L("Reveal in Finder")) { let urls = appState.queue.filter { items.contains($0.id) }.map { $0.video.fileURL }; if !urls.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(urls) } }; Divider(); Button(L("Remove Selected Tasks"), role: .destructive) { appState.queue.removeAll { items.contains($0.id) && $0.status != .processing } } }
            Divider()
            HStack {
                Button(L("Clear Done")) { appState.queue.removeAll { $0.status == .success } }.disabled(appState.queue.allSatisfy { $0.status != .success })
                Button(L("Write History")) { appState.showingHistory = true }
                Button(L("Retry Failed")) { appState.retryFailedItems() }
                    .disabled(appState.isProcessingQueue || !appState.queue.contains { $0.status == .error })
                Spacer()
                if appState.isProcessingQueue { ProgressView().controlSize(.small) }
                let waiting = appState.queue.filter { $0.status == .waiting }.count; let done = appState.queue.filter { $0.status == .success }.count
                if !appState.queue.isEmpty { Text("\(L("Waiting")) \(waiting) · \(L("Done")) \(done)").font(.caption).foregroundStyle(.secondary) }
                Button { appState.processQueue() } label: {
                    Label(L("Preview Writes"), systemImage: "doc.text.magnifyingglass")
                }.buttonStyle(.glassProminent).controlSize(.large)
                    .disabled(!appState.canProcessQueue)
                    .keyboardShortcut(.return, modifiers: [.command, .shift])
            }.padding(.horizontal, 16).padding(.vertical, 10).background(.bar)
        }
    }
    private func statusLabel(_ status: QueueItem.QueueStatus) -> String { switch status { case .waiting: return L("status.waiting"); case .processing: return L("status.processing"); case .success: return L("status.success"); case .error: return L("status.error") } }
    private func statusColor(_ status: QueueItem.QueueStatus) -> Color { switch status { case .success: return .green; case .error: return .red; case .processing: return .orange; case .waiting: return .secondary } }
}

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var selectedVideoIDs = Set<UUID>()
    @State private var viewMode = 0
    @State private var isImportingVideos = false
    let importNotifier = NotificationCenter.default.publisher(for: .init("TriggerImportVideos"))

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(selectedVideoIDs: $selectedVideoIDs, isImportingVideos: $isImportingVideos)
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 400)
        } detail: {
            // Keep the editor alive while inspecting the queue, preserving unsaved fields.
            ZStack {
                EditorDetailView(selectedVideoIDs: $selectedVideoIDs)
                    .opacity(viewMode == 0 ? 1 : 0)
                    .allowsHitTesting(viewMode == 0).accessibilityHidden(viewMode != 0)
                if viewMode == 1 { QueueView() }
            }
            .navigationTitle(viewMode == 0 ? L("Editor & Import") : L("Process Queue"))
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker(L("Workspace"), selection: $viewMode) {
                        Text(L("Editor & Import")).tag(0)
                        Text("\(L("Process Queue")) (\(appState.queue.count))").tag(1)
                    }.pickerStyle(.segmented).fixedSize()
                }
                if #available(macOS 27.0, *) {
                    ToolbarItem(placement: .primaryAction) { importButton }
                        .visibilityPriority(ToolbarItemVisibilityPriority(higherThan: .high))
                } else {
                    ToolbarItem(placement: .primaryAction) { importButton }
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .onReceive(importNotifier) { _ in isImportingVideos = true }
        .onAppear { selectedVideoIDs = appState.restoredSelection }
        .onChange(of: selectedVideoIDs) { _, ids in appState.restoredSelection = ids }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in appState.saveSessionNow() }
        .sheet(item: Binding(get: { appState.queuePreview }, set: { appState.queuePreview = $0 })) { preview in WritePreviewSheet(preview: preview) }
        .sheet(isPresented: Binding(get: { appState.showingHistory }, set: { appState.showingHistory = $0 })) { WriteHistorySheet() }
        .alert(L("File Access"), isPresented: Binding(get: { appState.accessError != nil && !appState.showingHistory && appState.queuePreview == nil }, set: { if !$0 { appState.accessError = nil } })) {
            Button(L("OK"), role: .cancel) { appState.accessError = nil }
        } message: { Text(appState.accessError ?? "") }
        .frame(minWidth: 980, minHeight: 640)
    }

    private var importButton: some View {
        Button { isImportingVideos = true } label: { Label(L("Import"), systemImage: "plus") }
            .help(L("Import Videos"))
    }
}

struct SidebarView: View {
    @Environment(AppState.self) private var appState
    @Binding var selectedVideoIDs: Set<UUID>
    @Binding var isImportingVideos: Bool
    @State private var previewURL: URL?
    @State private var search = ""
    @State private var issueFilter: LibraryIssue?

    private var visibleVideos: [VideoItem] {
        appState.importedVideos.filter { video in
            (search.isEmpty || video.fileName.localizedCaseInsensitiveContains(search)) &&
            (issueFilter == nil || appState.libraryIssues[video.id]?.contains(issueFilter!) == true)
        }
    }

    private func remove(_ ids: Set<UUID>) {
        appState.importedVideos.removeAll { ids.contains($0.id) }
        selectedVideoIDs.subtract(ids)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker(L("Library Filter"), selection: $issueFilter) {
                    Text(L("All Videos")).tag(nil as LibraryIssue?)
                    ForEach(LibraryIssue.allCases) { issue in Text(issue.title).tag(Optional(issue)) }
                }.labelsHidden()
                Button { appState.checkLibrary() } label: {
                    if appState.isCheckingLibrary { ProgressView().controlSize(.small) }
                    else { Image(systemName: "arrow.clockwise") }
                }.buttonStyle(.borderless).help(L("Check Library")).disabled(appState.isCheckingLibrary)
            }.padding(.horizontal, 10).padding(.bottom, 8)
            List(selection: $selectedVideoIDs) {
                ForEach(visibleVideos) { video in
                    HStack {
                        Text(video.fileName).lineLimit(2).truncationMode(.middle)
                        Spacer(minLength: 4)
                        if let issues = appState.libraryIssues[video.id], !issues.isEmpty {
                            Image(systemName: "exclamationmark.circle").foregroundStyle(.orange)
                                .help(issues.map(\.title).sorted().joined(separator: "、"))
                        }
                    }.tag(video.id)
                }
                .onDelete { indices in remove(Set(indices.map { visibleVideos[$0].id })) }
            }
            .overlay {
                if visibleVideos.isEmpty {
                    Text(appState.importedVideos.isEmpty ? L("Drop Videos Here") : L("No Matching Videos"))
                        .foregroundStyle(.secondary).font(.caption).allowsHitTesting(false)
                }
            }
            .contextMenu(forSelectionType: UUID.self) { ids in
                if !ids.isEmpty {
                    Button(L("Reveal in Finder")) { NSWorkspace.shared.activateFileViewerSelecting(appState.importedVideos.filter { ids.contains($0.id) }.map(\.fileURL)) }
                    if ids.count == 1, let video = appState.importedVideos.first(where: { ids.contains($0.id) }) {
                        Button(L("Restore NFO Backup")) { appState.previewBackupRestore(video) }.disabled(appState.isProcessingQueue)
                    }
                    Button(L("Remove from List"), role: .destructive) { remove(ids) }
                }
            }
            .scopedQuickLookPreview($previewURL)
            .onKeyPress(.space) {
                guard selectedVideoIDs.count == 1, let video = appState.importedVideos.first(where: { selectedVideoIDs.contains($0.id) }) else { return .ignored }
                previewURL = video.fileURL
                return .handled
            }
            Divider()
            HStack {
                Button { isImportingVideos = true } label: { Image(systemName: "plus") }.help(L("Import"))
                Button { remove(selectedVideoIDs) } label: { Image(systemName: "minus") }.disabled(selectedVideoIDs.isEmpty).help(L("Remove Selected"))
                Button { appState.toggleSort() } label: { Image(systemName: "arrow.up.arrow.down") }.help(L("Sort by Name"))
                Spacer()
                Text("\(visibleVideos.count)/\(appState.importedVideos.count)").font(.caption).foregroundStyle(.secondary)
            }.buttonStyle(.borderless).padding(12).background(.bar)
        }.navigationTitle(L("Import Videos")).frame(minWidth: 220, idealWidth: 260)
        .searchable(text: $search, placement: .sidebar, prompt: L("Search Videos"))
        .task { appState.checkLibrary() }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in let collector = DropCollector(); let group = DispatchGroup(); for provider in providers { group.enter(); _ = provider.loadObject(ofClass: URL.self) { url, _ in if let url = url { Task { await collector.add(url); group.leave() } } else { group.leave() } } }; group.notify(queue: .main) { Task { let finalURLs = await collector.urls; appState.importFiles(urls: finalURLs) } }; return true }
        .fileImporter(isPresented: $isImportingVideos, allowedContentTypes: [.audiovisualContent, .folder] + supportedVideoExtensions.compactMap { UTType(filenameExtension: $0) }, allowsMultipleSelection: true) { result in switch result {
            case .success(let urls): appState.importFiles(urls: urls)
            case .failure(let error): appState.accessError = error.localizedDescription
            } }
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
