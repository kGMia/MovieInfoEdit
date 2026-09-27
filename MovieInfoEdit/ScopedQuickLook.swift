import SwiftUI
import QuickLook

private struct ScopedQuickLook: ViewModifier {
    @Binding var url: URL?
    @State private var access: [URL] = []

    func body(content: Content) -> some View {
        content
            .quickLookPreview($url)
            .onChange(of: url) { _, newURL in
                SandboxAccessManager.shared.stopAccessing(access)
                access = newURL.map { SandboxAccessManager.shared.startAccessingFileAndParent(for: $0) } ?? []
            }
            .onDisappear {
                SandboxAccessManager.shared.stopAccessing(access)
                access = []
            }
    }
}

extension View {
    func scopedQuickLookPreview(_ url: Binding<URL?>) -> some View {
        modifier(ScopedQuickLook(url: url))
    }
}
