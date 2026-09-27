import Foundation

extension AppState {
    func scheduleSessionSave() {
        guard !restoringSession else { return }
        sessionSaveTask?.cancel()
        sessionSaveTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            saveSessionNow()
        }
    }

    func saveSessionNow() {
        do {
            try SessionStore.save(SessionSnapshot(videos: importedVideos, queue: queue, drafts: drafts, selectedIDs: restoredSelection))
        } catch { accessError = L("Session Save Failed") + "\n" + error.localizedDescription }
    }

    static func draftKey(_ ids: Set<UUID>) -> String { ids.map(\.uuidString).sorted().joined(separator: ",") }

    func saveDraft(_ data: NFOData, baseline: NFOData, ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        drafts[Self.draftKey(ids)] = EditorDraft(data: data, baseline: baseline)
    }

    func restoreSession() {
        restoringSession = true
        defer { restoringSession = false }
        do {
            if let session = try SessionStore.load() {
                importedVideos = session.videos.map { video in
                    var result = video
                    result.fileURL = SandboxAccessManager.shared.restoredURL(video.fileURL)
                    return result
                }
                queue = session.queue.map { item in
                    var result = item
                    result.video.fileURL = SandboxAccessManager.shared.restoredURL(item.video.fileURL)
                    result.nfoData = restoredArtwork(item.nfoData)
                    if result.status == .processing {
                        result.status = .error
                        result.errorMessage = L("Interrupted Write Hint")
                    }
                    return result
                }
                drafts = session.drafts.mapValues { EditorDraft(data: restoredArtwork($0.data), baseline: restoredArtwork($0.baseline)) }
                restoredSelection = session.selectedIDs.intersection(Set(importedVideos.map(\.id)))
            }
            history = try SessionStore.loadHistory()
        } catch { accessError = L("Session Restore Failed") + "\n" + error.localizedDescription }
    }

    private func restoredArtwork(_ data: NFOData) -> NFOData {
        var result = data
        result.posterURL = data.posterURL.map { SandboxAccessManager.shared.restoredURL($0) }
        result.fanartURLs = data.fanartURLs.map { SandboxAccessManager.shared.restoredURL($0) }
        return result
    }

    func undoWrite(_ record: UndoRecord) {
        guard !isProcessingQueue else { return }
        do {
            let restored = try NFOStore.undo(record.plan)
            if let index = importedVideos.firstIndex(where: { $0.id == restored.id }) { importedVideos[index] = restored }
            thumbnailsCache.removeValue(forKey: record.plan.updated.fileURL)
            drafts = drafts.filter { !$0.key.components(separatedBy: ",").contains(restored.id.uuidString) }
            queue.removeAll { $0.video.id == restored.id && $0.status == .success }
            try SessionStore.removeRecord(record)
            history.removeAll { $0.id == record.id }
            libraryIssues.removeValue(forKey: restored.id)
            editorReloadVideoID = restored.id
            editorReloadRevision += 1
            saveSessionNow()
        } catch { accessError = error.localizedDescription }
    }
}
