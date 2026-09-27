import Foundation

/// Writes sidecars as a unit. Read and validate every source before touching the media folder.
enum NFOStore {
    struct WriteError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static func prepare(video original: VideoItem, data: NFOData) throws -> WritePlan {
        let fm = FileManager.default
        var access = SandboxAccessManager.shared.startAccessingFileAndParent(for: original.fileURL)
        for url in [data.posterURL].compactMap({ $0 }) + data.fanartURLs {
            access += SandboxAccessManager.shared.startAccessingFileAndParent(for: url)
        }
        defer { SandboxAccessManager.shared.stopAccessing(access) }
        guard fm.fileExists(atPath: original.fileURL.path) else {
            throw CocoaError(.fileReadNoSuchFile)
        }

        var video = original
        let name = data.targetFilename.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty && name != original.baseName {
            guard name != ".", name != "..", !name.contains("/"), !name.contains(":"),
                  !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
                throw WriteError(message: L("Invalid Filename"))
            }
            video.fileURL = original.folderURL.appendingPathComponent(name).appendingPathExtension(original.fileURL.pathExtension)
            guard !fm.fileExists(atPath: video.fileURL.path) else { throw CocoaError(.fileWriteFileExists) }
        }
        let existingURL = findExistingNFOURL(for: original)
        let existingData = try existingURL.map { try Data(contentsOf: $0) }
        let document: XMLDocument
        let root: XMLElement
        if let existingData {
            document = try XMLDocument(data: existingData, options: [.nodePreserveAll, .nodeLoadExternalEntitiesNever])
            guard let element = document.rootElement(), element.name == "movie" else {
                throw WriteError(message: L("Invalid NFO"))
            }
            root = element
        } else {
            root = XMLElement(name: "movie")
            document = XMLDocument(rootElement: root)
        }
        document.characterEncoding = "UTF-8"
        document.version = "1.0"
        func replace(_ tag: String, with nodes: [XMLElement]) {
            root.elements(forName: tag).forEach { $0.detach() }
            nodes.forEach { root.addChild($0) }
        }
        func text(_ tag: String, _ value: String) {
            replace(tag, with: value.isEmpty ? [] : [XMLElement(name: tag, stringValue: value)])
        }
        try updateMovieDetails(data.details, in: root)
        text("title", data.title.isEmpty ? video.baseName : data.title)
        text("year", data.year)
        text("country", data.country)
        text("studio", data.studio)
        text("director", data.director)
        text("plot", data.plot)
        text("userrating", data.rating > 0 ? String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), data.rating) : "")
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.calendar = Calendar(identifier: .gregorian)
        df.dateFormat = "yyyy-MM-dd"
        text("premiered", data.enablePremiered ? df.string(from: data.premieredDate) : "")
        replace("genre", with: data.genres.map { XMLElement(name: "genre", stringValue: $0) })
        // Preserve actor metadata (thumb, order, IDs) when that actor is retained.
        let oldActors = root.elements(forName: "actor")
        replace("actor", with: data.actors.filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.map { actor in
            let node = oldActors.first(where: { firstText(in: $0, names: ["name"]) == actor.name })?.copy() as? XMLElement ?? XMLElement(name: "actor")
            for tag in ["name", "role"] { node.elements(forName: tag).forEach { $0.detach() } }
            node.addChild(XMLElement(name: "name", stringValue: actor.name))
            if !actor.role.isEmpty { node.addChild(XMLElement(name: "role", stringValue: actor.role)) }
            return node
        })

        var outputs: [(URL, Data)] = []
        func artworkName(_ source: URL, suffix: String) throws -> String {
            // This read also checks that same-folder artwork still exists and is accessible.
            let bytes = try Data(contentsOf: source)
            if source.deletingLastPathComponent().standardizedFileURL == video.folderURL.standardizedFileURL {
                return source.lastPathComponent
            }
            let target = video.folderURL.appendingPathComponent(video.baseName + suffix).appendingPathExtension(source.pathExtension)
            outputs.append((target, bytes))
            return target.lastPathComponent
        }
        let previous = parseExistingNFO(for: original)
        if data.posterURL != nil || previous?.posterURL != nil {
            root.elements(forName: "thumb").filter {
                let aspect = $0.attribute(forName: "aspect")?.stringValue
                return aspect == nil || aspect == "poster"
            }.forEach { $0.detach() }
            if let poster = data.posterURL {
                let thumb = XMLElement(name: "thumb", stringValue: try artworkName(poster, suffix: "-poster"))
                thumb.addAttribute(XMLNode.attribute(withName: "aspect", stringValue: "poster") as! XMLNode)
                root.addChild(thumb)
            }
        }
        if !data.fanartURLs.isEmpty || !(previous?.fanartURLs.isEmpty ?? true) {
            let fanart = XMLElement(name: "fanart")
            for (index, url) in data.fanartURLs.enumerated() {
                fanart.addChild(XMLElement(name: "thumb", stringValue: try artworkName(url, suffix: index == 0 ? "-fanart" : "-fanart\(index + 1)")))
            }
            replace("fanart", with: data.fanartURLs.isEmpty ? [] : [fanart])
        }
        let renamed = video.fileURL != original.fileURL
        let targetNFO = renamed ? video.folderURL.appendingPathComponent(video.baseName + ".nfo") : (existingURL ?? video.folderURL.appendingPathComponent(video.baseName + ".nfo"))
        if renamed && targetNFO != existingURL && fm.fileExists(atPath: targetNFO.path) {
            throw CocoaError(.fileWriteFileExists)
        }
        if let existingURL, let existingData {
            let backup = existingURL.appendingPathExtension("bak")
            // Keep the original backup across subsequent saves.
            if !fm.fileExists(atPath: backup.path) { outputs.append((backup, existingData)) }
        }
        outputs.append((targetNFO, document.xmlData(options: .nodePrettyPrint)))

        let changes = try outputs.map { url, bytes in
            FileChange(url: url, before: fm.fileExists(atPath: url.path) ? try Data(contentsOf: url) : nil, after: bytes)
        }
        return WritePlan(original: original, updated: video, changes: changes,
                         sourceNFO: existingURL, sourceBytes: existingData,
                         videoStamp: try VideoStamp(url: original.fileURL))
    }

    static func prepareBackupRestore(video: VideoItem) throws -> WritePlan {
        let access = SandboxAccessManager.shared.startAccessingFileAndParent(for: video.fileURL)
        defer { SandboxAccessManager.shared.stopAccessing(access) }
        guard let nfo = findExistingNFOURL(for: video) else { throw CocoaError(.fileReadNoSuchFile) }
        let before = try Data(contentsOf: nfo)
        let backup = try Data(contentsOf: nfo.appendingPathExtension("bak"))
        let document = try XMLDocument(data: backup, options: .nodeLoadExternalEntitiesNever)
        guard document.rootElement()?.name == "movie" else { throw WriteError(message: L("Invalid NFO")) }
        return WritePlan(original: video, updated: video, changes: [FileChange(url: nfo, before: before, after: backup)],
                         sourceNFO: nfo, sourceBytes: before, videoStamp: try VideoStamp(url: video.fileURL))
    }

    static func write(video: VideoItem, data: NFOData) throws -> VideoItem {
        let plan = try prepare(video: video, data: data)
        return try commit(plan)
    }

    static func commit(_ plan: WritePlan) throws -> VideoItem {
        try apply(plan, undo: false)
    }

    static func undo(_ plan: WritePlan) throws -> VideoItem {
        try apply(plan, undo: true)
    }

    private static func apply(_ plan: WritePlan, undo: Bool) throws -> VideoItem {
        let fm = FileManager.default
        let source = undo ? plan.updated : plan.original
        let target = undo ? plan.original : plan.updated
        var access = SandboxAccessManager.shared.startAccessingFileAndParent(for: source.fileURL)
        for change in plan.changes { access += SandboxAccessManager.shared.startAccessingFileAndParent(for: change.url) }
        defer { SandboxAccessManager.shared.stopAccessing(access) }
        guard try VideoStamp(url: source.fileURL) == plan.videoStamp else { throw WriteError(message: L("Files Changed Since Preview")) }
        let renamed = source.fileURL != target.fileURL
        if renamed && fm.fileExists(atPath: target.fileURL.path) { throw CocoaError(.fileWriteFileExists) }
        if !undo, let url = plan.sourceNFO, try Data(contentsOf: url) != plan.sourceBytes {
            throw WriteError(message: L("Files Changed Since Preview"))
        }
        // Refuse to overwrite subsequent edits, both at confirmation and during undo.
        for change in plan.changes {
            let current = fm.fileExists(atPath: change.url.path) ? try Data(contentsOf: change.url) : nil
            guard current == (undo ? change.after : change.before) else { throw WriteError(message: L("Files Changed Since Preview")) }
        }
        let changes = undo ? Array(plan.changes.reversed()) : plan.changes
        var applied: [FileChange] = []
        var moved = false
        func write(_ bytes: Data?, to url: URL) throws {
            if let bytes { try bytes.write(to: url, options: .atomic) }
            else { try fm.removeItem(at: url) }
        }
        do {
            if renamed { try fm.moveItem(at: source.fileURL, to: target.fileURL); moved = true }
            for change in changes {
                try write(undo ? change.before : change.after, to: change.url)
                applied.append(change)
            }
        } catch {
            var failures: [String] = []
            for change in applied.reversed() {
                do { try write(undo ? change.after : change.before, to: change.url) }
                catch { failures.append(error.localizedDescription) }
            }
            if moved {
                do { try fm.moveItem(at: target.fileURL, to: source.fileURL) }
                catch { failures.append(error.localizedDescription) }
            }
            if !failures.isEmpty { throw WriteError(message: error.localizedDescription + "\n" + L("Rollback Failed") + "\n" + failures.joined(separator: "\n")) }
            throw error
        }
        SandboxAccessManager.shared.bookmarkURL(target.fileURL)
        return target
    }

}

extension NFOData {
    /// Apply only fields changed from the batch editor's initial intersection.
    func applyingChanges(from baseline: NFOData, to original: NFOData) -> NFOData {
        var result = original
        if title != baseline.title { result.title = title }
        if year != baseline.year { result.year = year }
        if country != baseline.country { result.country = country }
        if studio != baseline.studio { result.studio = studio }
        if director != baseline.director { result.director = director }
        if plot != baseline.plot { result.plot = plot }
        if rating != baseline.rating { result.rating = rating }
        if enablePremiered != baseline.enablePremiered || (enablePremiered && premieredDate != baseline.premieredDate) {
            result.enablePremiered = enablePremiered
            result.premieredDate = premieredDate
        }
        if genres != baseline.genres { result.genres = genres }
        if actors.map(\.name) != baseline.actors.map(\.name) || actors.map(\.role) != baseline.actors.map(\.role) { result.actors = actors }
        if posterURL != baseline.posterURL { result.posterURL = posterURL }
        if fanartURLs != baseline.fanartURLs { result.fanartURLs = fanartURLs }
        if let edited = details {
            let initial = baseline.details ?? MovieDetails()
            var merged = original.details ?? MovieDetails()
            for key in MovieDetails.allKeys where edited[keyPath: key] != initial[keyPath: key] {
                merged[keyPath: key] = edited[keyPath: key]
            }
            result.details = merged
        }
        result.targetFilename = ""
        return result
    }
}

private func updateMovieDetails(_ edited: MovieDetails?, in root: XMLElement) throws {
    guard let edited else { return } // Backward-compatible queued snapshots.
    let old = readMovieDetails(root)
    func replace(_ tag: String, _ values: [String]) {
        root.elements(forName: tag).forEach { $0.detach() }
        for value in values where !value.isEmpty { root.addChild(XMLElement(name: tag, stringValue: value)) }
    }
    for field in MovieDetails.textFields where edited[keyPath: field.key] != old[keyPath: field.key] {
        let value = edited[keyPath: field.key].trimmingCharacters(in: .whitespacesAndNewlines)
        if field.tag == "runtime", !value.isEmpty, Int(value).map({ $0 >= 0 }) != true {
            throw NFOStore.WriteError(message: L("Runtime Validation"))
        }
        replace(field.tag, [value])
    }
    if edited.writers != old.writers { replace("credits", MovieDetails.entries(edited.writers)) }
    if edited.tags != old.tags { replace("tag", MovieDetails.entries(edited.tags)) }
    if edited.setName != old.setName || edited.setOverview != old.setOverview {
        let name = edited.setName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty || edited.setOverview.isEmpty else { throw NFOStore.WriteError(message: L("Collection Validation")) }
        let existing = root.elements(forName: "set").first
        let node = existing?.copy() as? XMLElement ?? XMLElement(name: "set")
        if node.elements(forName: "name").isEmpty { node.stringValue = nil }
        for tag in ["name", "overview"] { node.elements(forName: tag).forEach { $0.detach() } }
        root.elements(forName: "set").forEach { $0.detach() }
        if !name.isEmpty {
            node.addChild(XMLElement(name: "name", stringValue: name))
            if !edited.setOverview.isEmpty { node.addChild(XMLElement(name: "overview", stringValue: edited.setOverview)) }
            root.addChild(node)
        }
    }
    for (type, key) in [("imdb", \MovieDetails.imdbID), ("tmdb", \MovieDetails.tmdbID)] where edited[keyPath: key] != old[keyPath: key] {
        let value = edited[keyPath: key].trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = type == "imdb" ? "^tt[0-9]+$" : "^[1-9][0-9]*$"
        guard value.isEmpty || value.range(of: pattern, options: .regularExpression) != nil else {
            throw NFOStore.WriteError(message: L("ID Validation") + " (" + type.uppercased() + ")")
        }
        let existing = root.elements(forName: "uniqueid").filter { $0.attribute(forName: "type")?.stringValue?.lowercased() == type }
        let node = existing.first?.copy() as? XMLElement ?? XMLElement(name: "uniqueid")
        existing.forEach { $0.detach() }
        if !value.isEmpty {
            node.stringValue = value
            if node.attribute(forName: "type") == nil { node.addAttribute(XMLNode.attribute(withName: "type", stringValue: type) as! XMLNode) }
            root.addChild(node)
        }
    }
    // If the user removed the default ID, choose one remaining provider without deleting custom IDs.
    let ids = root.elements(forName: "uniqueid")
    if (edited.imdbID != old.imdbID || edited.tmdbID != old.tmdbID), !ids.isEmpty, !ids.contains(where: { $0.attribute(forName: "default")?.stringValue == "true" }) {
        ids[0].removeAttribute(forName: "default")
        ids[0].addAttribute(XMLNode.attribute(withName: "default", stringValue: "true") as! XMLNode)
    }
}
