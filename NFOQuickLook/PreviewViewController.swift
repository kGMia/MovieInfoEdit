import AppKit
import Quartz
import SwiftUI

final class PreviewViewController: NSViewController, QLPreviewingController {
    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 720, height: 580))
    }

    func preparePreviewOfFile(at url: URL) async throws {
        let document = try NFOPreviewDocument.read(url)
        let hosting = NSHostingView(rootView: NFOPreviewView(document: document))
        hosting.translatesAutoresizingMaskIntoConstraints = false
        view.subviews.forEach { $0.removeFromSuperview() }
        view.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: view.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        preferredContentSize = NSSize(width: 720, height: 580)
    }
}

private struct NFOPreviewView: View {
    let document: NFOPreviewDocument
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Label(document.title, systemImage: document.isStructured ? "film" : "doc.text")
                    .font(.largeTitle.bold())
                if document.isStructured {
                    Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 10) {
                        ForEach(document.fields.indices, id: \.self) { index in
                            GridRow {
                                Text(LocalizedStringKey(document.fields[index].label)).foregroundStyle(.secondary)
                                Text(document.fields[index].value)
                            }
                        }
                    }
                    if !document.plot.isEmpty {
                        Divider()
                        Text("Plot").font(.headline)
                        Text(document.plot).lineSpacing(5)
                    }
                    if !document.actors.isEmpty {
                        Divider()
                        Text("Actors").font(.headline)
                        Text(document.actors.joined(separator: "\n")).lineSpacing(5)
                    }
                    DisclosureGroup("NFO Source") { Text(document.sourceText).font(.system(.caption, design: .monospaced)).frame(maxWidth: .infinity, alignment: .leading) }
                } else {
                    Text(document.sourceText).font(.system(.body, design: .monospaced))
                }
            }.textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(28)
        }.background(.background)
    }
}
