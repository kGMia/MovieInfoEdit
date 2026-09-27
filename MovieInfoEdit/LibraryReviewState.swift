import Foundation

extension AppState {
    func checkLibrary() {
        libraryCheckTask?.cancel()
        let videos = importedVideos
        isCheckingLibrary = true
        libraryCheckTask = Task {
            var results: [UUID: Set<LibraryIssue>] = [:]
            for video in videos {
                guard !Task.isCancelled else { return }
                results[video.id] = LibraryReview.inspect(video)
                await Task.yield()
            }
            let targets = Dictionary(grouping: queue.filter { $0.status == .waiting || $0.status == .error }) { item in
                let name = item.nfoData.targetFilename.trimmingCharacters(in: .whitespacesAndNewlines)
                return item.video.folderURL.appendingPathComponent((name.isEmpty ? item.video.baseName : name) + ".nfo").standardizedFileURL.path.lowercased()
            }
            for items in targets.values {
                for item in items {
                    let name = item.nfoData.targetFilename.trimmingCharacters(in: .whitespacesAndNewlines)
                    let access = SandboxAccessManager.shared.startAccessingFileAndParent(for: item.video.fileURL)
                    defer { SandboxAccessManager.shared.stopAccessing(access) }
                    let renamed = !name.isEmpty && name != item.video.baseName
                    let existingTarget = renamed && (FileManager.default.fileExists(atPath: item.video.folderURL.appendingPathComponent(name + "." + item.video.fileURL.pathExtension).path) || FileManager.default.fileExists(atPath: item.video.folderURL.appendingPathComponent(name + ".nfo").path))
                    if items.count > 1 || existingTarget { results[item.video.id, default: []].insert(.conflict) }
                }
            }
            guard !Task.isCancelled else { return }
            libraryIssues = results
            isCheckingLibrary = false
        }
    }
}
