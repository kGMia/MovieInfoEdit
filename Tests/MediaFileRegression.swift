import Foundation
import AppKit

@main
struct MediaFileRegression {
    @MainActor
    static func main() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("MovieInfoEdit-tests-" + UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        var assertions = 0
        func check(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
            guard try condition() else { fatalError(message) }
            assertions += 1
        }
        func fixture(_ folder: String, _ name: String, _ contents: String = "fixture") throws -> URL {
            let dir = root.appendingPathComponent(folder, isDirectory: true)
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = dir.appendingPathComponent(name)
            try Data(contents.utf8).write(to: url)
            return try fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil).first { $0.lastPathComponent == name }!
        }
        let single = VideoItem(fileURL: try fixture("single", "Film.mkv"))
        let fanart = try fixture("single", "Film-fanart.jpg")
        try check(artworkRank(for: fanart, baseName: "Film", singleVideoFolder: true) == 10, "Fanart classified as poster")
        try check(discoverLocalArtwork(for: single.fileURL).posterURL == nil, "Fanart chosen as poster")
        try check(discoverLocalArtwork(for: single.fileURL).fanartURLs == [fanart], "Fanart missing")
        let poster = try fixture("single", "Film-poster.png")
        try check(discoverLocalArtwork(for: single.fileURL).posterURL == poster, "Local poster missing")
        let nfo = try fixture("single", "FILM.NFO", """
        <movie><title>Original &amp; title</title><year>2024</year><plot>Keep my plot</plot>
        <uniqueid type="tmdb">1234</uniqueid><custom>Keep me</custom>
        <actor><name>Alice</name><role>Lead</role><thumb>https://example.invalid/actor.jpg</thumb></actor>
        <ratings><rating name="tmdb"><value>8.2</value></rating></ratings>
        <thumb aspect="poster">Film-poster.png</thumb></movie>
        """)
        try check(findExistingNFOURL(for: single)?.lastPathComponent.lowercased() == nfo.lastPathComponent.lowercased(), "Case-insensitive NFO lookup failed")
        let parsed = parseExistingNFO(for: single)!
        try check(parsed.title == "Original & title" && parsed.rating == 8.2, "NFO parsing failed")
        try check(parsed.actors.first?.role == "Lead", "Actor role lost")

        let other = VideoItem(fileURL: try fixture("multi", "Other.mkv"))
        _ = try fixture("multi", "Film.mp4")
        _ = try fixture("multi", "Film.nfo", "<movie><title>Wrong movie</title></movie>")
        _ = try fixture("multi", "movie.nfo", "<movie><title>Also wrong</title></movie>")
        try check(findExistingNFOURL(for: other) == nil, "Cross-movie NFO contamination")
        let lone = VideoItem(fileURL: try fixture("lone", "Feature.mp4"))
        let shared = try fixture("lone", "movie.nfo", "<movie><title>Folder title</title></movie>")
        try check(findExistingNFOURL(for: lone) == shared, "Single folder fallback failed")

        let baseline = NFOData()
        var changes = baseline
        changes.studio = "New Studio"
        let merged = changes.applyingChanges(from: baseline, to: parsed)
        try check(merged.title == parsed.title && merged.plot == parsed.plot && merged.rating == parsed.rating, "Batch erased unedited fields")
        try check(merged.posterURL == poster && merged.actors.first?.name == "Alice", "Batch erased artwork or actors")
        try check(merged.studio == "New Studio", "Batch edit not applied")
        var clearBaseline = parsed
        clearBaseline.studio = "Old Studio"
        var clear = clearBaseline
        clear.studio = ""
        try check(clear.applyingChanges(from: clearBaseline, to: clearBaseline).studio.isEmpty, "Explicit clearing failed")

        let oldBytes = try Data(contentsOf: nfo)
        var edit = parsed
        edit.title = "New <Title> & Friends"
        let special = try fixture("outside", "cover & art.png", "PNG fixture")
        edit.posterURL = special
        _ = try NFOStore.write(video: single, data: edit)
        let written = try XMLDocument(contentsOf: nfo, options: .nodeLoadExternalEntitiesNever)
        let element = written.rootElement()!
        try check(firstText(in: element, names: ["title"]) == edit.title, "XML escaping failed")
        try check(firstText(in: element, names: ["custom"]) == "Keep me", "Unknown NFO field lost")
        try check(element.elements(forName: "uniqueid").first?.stringValue == "1234", "Provider ID lost")
        try check(element.elements(forName: "actor").first?.elements(forName: "thumb").first != nil, "Actor extra metadata lost")
        try check(Data(contentsOf: nfo.appendingPathExtension("bak")) == oldBytes, "Original backup missing")
        try check(firstText(in: element, names: ["thumb"]) == "Film-poster.png", "Image extension changed")
        try check(Data(contentsOf: poster) == Data("PNG fixture".utf8), "Artwork copy failed")
        let withSpecialName = try fixture("single", "poster & local.jpg")
        edit.posterURL = withSpecialName
        _ = try NFOStore.write(video: single, data: edit)
        let escapedArt = try XMLDocument(contentsOf: nfo, options: .nodeLoadExternalEntitiesNever)
        try check(firstText(in: escapedArt.rootElement()!, names: ["thumb"]) == "poster & local.jpg", "Artwork filename escaping failed")
        try check(Data(contentsOf: nfo.appendingPathExtension("bak")) == oldBytes, "Original backup overwritten")

        let bytesBeforeFailure = try Data(contentsOf: nfo)
        edit.targetFilename = "../escape"
        do { _ = try NFOStore.write(video: single, data: edit); fatalError("Unsafe rename accepted") } catch {}
        try check(fm.fileExists(atPath: single.fileURL.path), "Unsafe rename modified video")
        edit.targetFilename = "Renamed"
        edit.posterURL = root.appendingPathComponent("missing.jpg")
        do { _ = try NFOStore.write(video: single, data: edit); fatalError("Missing artwork accepted") } catch {}
        try check(fm.fileExists(atPath: single.fileURL.path) && !fm.fileExists(atPath: single.folderURL.appendingPathComponent("Renamed.mkv").path), "Failure partially renamed video")
        try check(Data(contentsOf: nfo) == bytesBeforeFailure, "Failed write corrupted NFO")
        edit.posterURL = poster
        let collision = try fixture("single", "Renamed.mkv")
        do { _ = try NFOStore.write(video: single, data: edit); fatalError("Rename collision accepted") } catch {}
        try check(String(contentsOf: collision, encoding: .utf8) == "fixture", "Collision overwritten")
        try fm.removeItem(at: collision)
        let renamed = try NFOStore.write(video: single, data: edit)
        try check(renamed.fileURL.lastPathComponent == "Renamed.mkv" && fm.fileExists(atPath: renamed.fileURL.path), "Rename failed")
        try check(parseExistingNFO(for: renamed)?.title == edit.title, "Renamed video lost NFO")
        let invalid = VideoItem(fileURL: try fixture("invalid", "Broken.mkv"))
        let invalidNFO = try fixture("invalid", "Broken.nfo", "<movie><title>truncated")
        do { _ = try NFOStore.write(video: invalid, data: NFOData()); fatalError("Malformed NFO overwritten") } catch {}
        try check(String(contentsOf: invalidNFO, encoding: .utf8) == "<movie><title>truncated", "Invalid NFO was destroyed")
        // Preview is read-only; commit and undo protect edits made after either operation.
        let plannedVideo = VideoItem(fileURL: try fixture("plans", "Before.mkv"))
        let plannedNFO = try fixture("plans", "Before.nfo", "<movie><title>Before</title><year>2020</year></movie>")
        var plannedData = parseExistingNFO(for: plannedVideo)!
        plannedData.title = "After"
        plannedData.targetFilename = "After"
        let plan = try NFOStore.prepare(video: plannedVideo, data: plannedData)
        try check(parseExistingNFO(for: plannedVideo)?.title == "Before", "Preview wrote metadata")
        try check(fm.fileExists(atPath: plannedVideo.fileURL.path), "Preview renamed video")
        try check(plan.fieldChanges.contains { $0.id == "title" && $0.before == "Before" && $0.after == "After" }, "Preview omitted changed title")
        let planRoundTrip = try JSONDecoder().decode(WritePlan.self, from: JSONEncoder().encode(plan))
        try check(planRoundTrip.original.id == plannedVideo.id, "Write receipt changed video identity")
        _ = try NFOStore.commit(plan)
        try check(parseExistingNFO(for: plan.updated)?.title == "After", "Confirmed preview did not write")
        let updatedNFO = plan.outputNFO!.url
        let expectedBytes = try Data(contentsOf: updatedNFO)
        try Data("<movie><title>Edited elsewhere</title></movie>".utf8).write(to: updatedNFO)
        do { _ = try NFOStore.undo(plan); fatalError("Undo overwrote external edits") } catch {}
        try check(String(contentsOf: updatedNFO, encoding: .utf8).contains("Edited elsewhere"), "Undo damaged newer edit")
        try expectedBytes.write(to: updatedNFO)
        _ = try NFOStore.undo(plan)
        try check(fm.fileExists(atPath: plannedVideo.fileURL.path) && !fm.fileExists(atPath: plan.updated.fileURL.path), "Undo failed to restore video name")
        try check(parseExistingNFO(for: plannedVideo)?.title == "Before" && !fm.fileExists(atPath: updatedNFO.path), "Undo failed to restore NFO outputs")
        let stalePlan = try NFOStore.prepare(video: plannedVideo, data: plannedData)
        try Data("<movie><title>New source</title></movie>".utf8).write(to: plannedNFO)
        do { _ = try NFOStore.commit(stalePlan); fatalError("Stale preview committed") } catch {}
        try check(fm.fileExists(atPath: plannedVideo.fileURL.path), "Stale preview partially renamed video")

        let backupURL = plannedNFO.appendingPathExtension("bak")
        try Data("<movie><title>Backup title</title></movie>".utf8).write(to: backupURL)
        let restorePlan = try NFOStore.prepareBackupRestore(video: plannedVideo)
        try check(parseExistingNFO(for: plannedVideo)?.title == "New source", "Backup restore preview mutated files")
        _ = try NFOStore.commit(restorePlan)
        try check(parseExistingNFO(for: plannedVideo)?.title == "Backup title", "Backup restore failed")
        _ = try NFOStore.undo(restorePlan)
        try check(parseExistingNFO(for: plannedVideo)?.title == "New source", "Backup restore was not undoable")
        let sessionURL = root.appendingPathComponent("session.json")
        let queued = QueueItem(video: plannedVideo, nfoData: plannedData)
        let snapshot = SessionSnapshot(videos: [plannedVideo], queue: [queued], drafts: ["test": EditorDraft(data: plannedData, baseline: NFOData())], selectedIDs: [plannedVideo.id])
        try SessionStore.save(snapshot, to: sessionURL)
        let restored = try SessionStore.load(from: sessionURL)!
        try check(restored.videos[0].id == plannedVideo.id && restored.queue[0].id == queued.id, "Session changed persistent IDs")
        try check(restored.drafts["test"]?.data.title == "After" && restored.selectedIDs == [plannedVideo.id], "Draft or selection not restored")
        let previewDoc = NFOPreviewDocument.parse(Data("<movie><title>A &amp; B</title><year>2026</year><plot>Story</plot><actor><name>Alice</name><role>Lead</role></actor></movie>".utf8), filename: "film")
        try check(previewDoc.isStructured && previewDoc.title == "A & B" && previewDoc.plot == "Story", "Quick Look metadata parsing failed")
        try check(previewDoc.actors == ["Alice — Lead"], "Quick Look cast missing")
        let plainPreview = NFOPreviewDocument.parse(Data("plain NFO text".utf8), filename: "legacy")
        try check(!plainPreview.isStructured && plainPreview.sourceText == "plain NFO text", "Plain NFO fallback failed")
        let entity = NFOPreviewDocument.parse(Data("<!DOCTYPE movie [<!ENTITY secret SYSTEM 'file:///etc/passwd'>]><movie><title>&secret;</title></movie>".utf8), filename: "entity")
        try check(!entity.isStructured && entity.title == "entity", "External entity was evaluated")
        let issues = LibraryReview.inspect(invalid)
        try check(issues.contains(.invalidNFO), "Library failed to identify invalid NFO")
        try check(LibraryReview.inspect(other).contains(.missingNFO), "Library failed to identify missing NFO")
        // Extended metadata: round trip, legacy snapshots, per-field batches, validation and undo.
        let extendedVideo = VideoItem(fileURL: try fixture("extended", "Feature.mkv"))
        let extendedURL = try fixture("extended", "Feature.nfo", """
        <movie><title>Feature</title><originaltitle>Original</originaltitle><sorttitle>Sort</sorttitle>
        <tagline>Catchphrase</tagline><outline>Short story</outline><runtime>123</runtime><mpaa>PG-13</mpaa>
        <credits>Writer A</credits><credits>Writer B</credits><tag>Tag A</tag><tag>Tag B</tag>
        <set custom="keep"><name>Series</name><overview>Series story</overview><custom>Keep set child</custom></set>
        <uniqueid type="imdb" default="true" custom="keep">tt1234567</uniqueid>
        <uniqueid type="tmdb">123</uniqueid><uniqueid type="custom" default="false">keep-provider</uniqueid>
        <trailer>https://example.invalid/trailer</trailer></movie>
        """)
        let extended = parseExistingNFO(for: extendedVideo)!
        try check(extended.details?.originalTitle == "Original" && extended.details?.runtime == "123", "Extended scalar parsing failed")
        try check(extended.details?.writers == "Writer A; Writer B" && extended.details?.tags == "Tag A; Tag B", "Repeated metadata parsing failed")
        try check(extended.details?.setName == "Series" && extended.details?.setOverview == "Series story", "Collection parsing failed")
        try check(extended.details?.imdbID == "tt1234567" && extended.details?.tmdbID == "123", "Provider IDs missing")
        let legacy = try JSONDecoder().decode(NFOData.self, from: JSONEncoder().encode(NFOData()))
        try check(legacy.details == nil, "Old draft schema no longer decodes")
        let legacyPlan = try NFOStore.prepare(video: extendedVideo, data: legacy)
        let legacyRoot = try XMLDocument(data: legacyPlan.outputNFO!.after).rootElement()!
        try check(readMovieDetails(legacyRoot) == extended.details, "Old queue overwrote extended fields")
        var edited = extended
        edited.details!.originalTitle = "New <Original> & Title"
        edited.details!.sortTitle = ""
        edited.details!.writers = "New Writer; Second Writer；New Writer"
        edited.details!.tags = "One\nTwo"
        edited.details!.setName = "New Series"
        edited.details!.imdbID = "tt7654321"
        let extendedPlan = try NFOStore.prepare(video: extendedVideo, data: edited)
        try check(extendedPlan.fieldChanges.contains { $0.id == "originaltitle" }, "Extended edits missing in preview")
        _ = try NFOStore.commit(extendedPlan)
        let extendedResult = parseExistingNFO(for: extendedVideo)!
        try check(extendedResult.details?.originalTitle == "New <Original> & Title" && extendedResult.details?.sortTitle == "", "Extended text escaping or clearing failed")
        try check(extendedResult.details?.writers == "New Writer; Second Writer" && extendedResult.details?.tags == "One; Two", "Repeated values did not normalize")
        let extendedRoot = try XMLDocument(contentsOf: extendedURL).rootElement()!
        try check(extendedRoot.elements(forName: "set").first?.elements(forName: "custom").first?.stringValue == "Keep set child", "Collection custom node lost")
        try check(extendedRoot.elements(forName: "uniqueid").contains { $0.stringValue == "keep-provider" }, "Unknown provider lost")
        try check(extendedRoot.elements(forName: "uniqueid").first { $0.stringValue == "tt7654321" }?.attribute(forName: "custom")?.stringValue == "keep", "ID attributes lost")
        _ = try NFOStore.undo(extendedPlan)
        try check(parseExistingNFO(for: extendedVideo)?.details == extended.details, "Extended undo failed")
        var batchBase = NFOData(); batchBase.details = MovieDetails()
        var batchEdit = batchBase; batchEdit.details!.certification = "R"
        let batchResult = batchEdit.applyingChanges(from: batchBase, to: extended)
        try check(batchResult.details?.certification == "R" && batchResult.details?.imdbID == "tt1234567" && batchResult.details?.setName == "Series", "Batch changed unrelated extended fields")
        var clearDetails = extended; clearDetails.details!.tagline = ""
        try check(clearDetails.applyingChanges(from: extended, to: extended).details?.tagline == "", "Batch extended clearing failed")
        for (key, value) in [(\MovieDetails.runtime, "-1"), (\MovieDetails.imdbID, "abc"), (\MovieDetails.tmdbID, "0")] {
            var invalidDetails = extended; invalidDetails.details![keyPath: key] = value
            do { _ = try NFOStore.prepare(video: extendedVideo, data: invalidDetails); fatalError("Invalid extended field accepted") } catch {}
        }
        try check(parseExistingNFO(for: extendedVideo)?.details == extended.details, "Validation changed source files")
        let extendedPreview = try NFOPreviewDocument.read(extendedURL)
        try check(extendedPreview.fields.contains { $0.label == "Collection" && $0.value == "Series" }, "Quick Look omitted collection")
        try check(extendedPreview.fields.contains { $0.label == "IMDB ID" && $0.value == "tt1234567" }, "Quick Look omitted provider ID")
        // Large originals remain untouched; the UI receives a bounded, orientation-aware thumbnail.
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1800, pixelsHigh: 1200, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let originalImage = bitmap.representation(using: .png, properties: [:])!
        let imageURL = root.appendingPathComponent("large.png")
        try originalImage.write(to: imageURL)
        let thumbnail = await loadArtworkThumbnail(at: imageURL)
        let thumbRep = thumbnail?.representations.first
        try check(thumbRep?.pixelsWide == 512 && (thumbRep?.pixelsHigh ?? 0) <= 512, "Thumbnail was not downsampled")
        try check(Data(contentsOf: imageURL) == originalImage, "Thumbnail generation modified original artwork")
        let cachedThumbnail = await loadArtworkThumbnail(at: imageURL)
        try check(cachedThumbnail != nil, "Cached thumbnail missing")
        try Data("invalid image".utf8).write(to: imageURL)
        let replacedThumbnail = await loadArtworkThumbnail(at: imageURL)
        try check(replacedThumbnail == nil, "Thumbnail cache retained an externally replaced image")
        // Reading runtime preserves per-video values in drafts and resolves each queue snapshot.
        try check(runtimeMinutes(seconds: 5) == "1" && runtimeMinutes(seconds: 90) == "2", "Runtime rounding failed")
        try check(runtimeMinutes(seconds: 0) == nil && runtimeMinutes(seconds: .nan) == nil && runtimeMinutes(seconds: .infinity) == nil, "Invalid duration accepted")
        let secondID = UUID()
        var runtimes = extended
        runtimes.runtimeByVideoID = [extendedVideo.id.uuidString: "91", secondID.uuidString: "123"]
        let restoredRuntimes = try JSONDecoder().decode(NFOData.self, from: JSONEncoder().encode(runtimes))
        try check(restoredRuntimes.resolvingRuntime(for: extendedVideo.id).details?.runtime == "91", "First batch runtime was not restored")
        try check(restoredRuntimes.resolvingRuntime(for: secondID).details?.runtime == "123", "Batch reused another video's runtime")
        try check(restoredRuntimes.resolvingRuntime(for: secondID).runtimeByVideoID == nil, "Per-video draft state leaked into queue snapshot")
        try check(legacy.runtimeByVideoID == nil, "Legacy runtime draft schema failed")
        var manualRuntime = runtimes
        manualRuntime.runtimeByVideoID = nil
        manualRuntime.details!.runtime = "140"
        try check(manualRuntime.resolvingRuntime(for: secondID).details?.runtime == "140", "Manual runtime failed to override automatic values")
        // A local PCM fixture exercises AVFoundation without user media or network access.
        var wav = Data("RIFF".utf8)
        func appendLE<T: FixedWidthInteger>(_ number: T) {
            var littleEndian = number.littleEndian
            withUnsafeBytes(of: &littleEndian) { wav.append(contentsOf: $0) }
        }
        let sampleCount = 8000 * 90
        appendLE(UInt32(36 + sampleCount)); wav.append(Data("WAVEfmt ".utf8))
        appendLE(UInt32(16)); appendLE(UInt16(1)); appendLE(UInt16(1))
        appendLE(UInt32(8000)); appendLE(UInt32(8000)); appendLE(UInt16(1)); appendLE(UInt16(8))
        wav.append(Data("data".utf8)); appendLE(UInt32(sampleCount))
        wav.append(Data(repeating: 128, count: sampleCount))
        let durationURL = root.appendingPathComponent("runtime.wav")
        try wav.write(to: durationURL)
        let readMinutes = try await readRuntimeMinutes(at: durationURL)
        try check(readMinutes == "2", "AVFoundation runtime reading failed")
        var rejectedUnreadableRuntime = false
        do { _ = try await readRuntimeMinutes(at: root.appendingPathComponent("missing.mkv")) }
        catch { rejectedUnreadableRuntime = true }
        try check(rejectedUnreadableRuntime, "Missing media produced a runtime")
        print("PASS: \(assertions) media/NFO regression assertions")
    }
}
