import Foundation

/// Pure text/XML parsing shared with the regression suite. No HTML or network resources are loaded.
struct NFOPreviewDocument {
    var title: String
    var fields: [(label: String, value: String)] = []
    var plot = ""
    var actors: [String] = []
    var sourceText = ""
    var isStructured = false

    static let maximumBytes = 2 * 1024 * 1024

    static func read(_ url: URL) throws -> NFOPreviewDocument {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        let bytes = try file.read(upToCount: maximumBytes + 1) ?? Data()
        guard bytes.count <= maximumBytes else { throw CocoaError(.fileReadTooLarge) }
        return parse(bytes, filename: url.deletingPathExtension().lastPathComponent)
    }

    static func parse(_ bytes: Data, filename: String) -> NFOPreviewDocument {
        let text = String(data: bytes, encoding: .utf8) ?? String(data: bytes, encoding: .utf16) ?? String(data: bytes, encoding: .isoLatin1) ?? ""
        var result = NFOPreviewDocument(title: filename, sourceText: text)
        // Reject DTD/entity expansion, including internal entities; render the source as plain text instead.
        guard bytes.count <= maximumBytes, !text.uppercased().contains("<!DOCTYPE"), !text.uppercased().contains("<!ENTITY"),
              let root = (try? XMLDocument(data: bytes, options: .nodeLoadExternalEntitiesNever))?.rootElement(),
              ["movie", "tvshow", "episodedetails", "musicvideo"].contains(root.name ?? "") else { return result }
        func value(_ names: [String]) -> String {
            for name in names {
                let values = root.elements(forName: name).compactMap { $0.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                if !values.isEmpty { return values.joined(separator: " · ") }
            }
            return ""
        }
        result.isStructured = true
        let title = value(["title", "originaltitle"])
        if !title.isEmpty { result.title = title }
        for (label, names) in [("Original Title", ["originaltitle"]), ("Sort Title", ["sorttitle"]), ("Tagline", ["tagline"]), ("Runtime Minutes", ["runtime"]), ("Certification", ["mpaa"]), ("Writers", ["credits"]), ("Tags", ["tag"]), ("Trailer", ["trailer"]), ("Year", ["year"]), ("Premiered", ["premiered", "releasedate"]), ("Genres", ["genre"]), ("Country", ["country"]), ("Director", ["director"]), ("Studio", ["studio"]), ("Rating", ["userrating", "rating"])] {
            let text = value(names)
            if !text.isEmpty { result.fields.append((label, text)) }
        }
        if let collection = root.elements(forName: "set").first {
            let name = collection.elements(forName: "name").first?.stringValue ?? collection.stringValue ?? ""
            if !name.isEmpty { result.fields.append(("Collection", name)) }
            if let overview = collection.elements(forName: "overview").first?.stringValue, !overview.isEmpty { result.fields.append(("Collection Overview", overview)) }
        }
        for id in root.elements(forName: "uniqueid") {
            if let type = id.attribute(forName: "type")?.stringValue, let value = id.stringValue, !value.isEmpty {
                result.fields.append((type.uppercased() + " ID", value))
            }
        }
        if !value(["plot"]).isEmpty, !value(["outline"]).isEmpty {
            result.fields.append(("Outline", value(["outline"])))
        }
        result.plot = value(["plot", "outline"])
        result.actors = root.elements(forName: "actor").compactMap { actor in
            let name = actor.elements(forName: "name").first?.stringValue ?? ""
            let role = actor.elements(forName: "role").first?.stringValue ?? ""
            return name.isEmpty ? nil : name + (role.isEmpty ? "" : " — " + role)
        }
        return result
    }
}
