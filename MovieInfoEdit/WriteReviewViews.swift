import SwiftUI

struct WritePreviewSheet: View {
    @Environment(AppState.self) private var appState
    let preview: QueuePreview

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L("Preview Writes")).font(.title2.bold())
            Text(L("Preview Writes Hint")).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(preview.errors, id: \.self) { error in Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red).textSelection(.enabled) }
                    ForEach(preview.order, id: \.self) { id in
                        if let plan = preview.plans[id] {
                            GroupBox(plan.original.fileName) {
                                VStack(alignment: .leading, spacing: 12) {
                                    if plan.renamed { Label(plan.original.fileName + " → " + plan.updated.fileName, systemImage: "pencil") }
                                    if plan.fieldChanges.isEmpty { Text(L("No Field Changes")).foregroundStyle(.secondary) }
                                    ForEach(plan.fieldChanges) { field in
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(field.label).font(.caption.bold())
                                            Text("− " + (field.before.isEmpty ? "∅" : field.before)).foregroundStyle(.secondary)
                                            Text("+ " + (field.after.isEmpty ? "∅" : field.after)).foregroundStyle(.primary)
                                        }.textSelection(.enabled)
                                    }
                                    Divider()
                                    ForEach(plan.changes, id: \.url) { change in
                                        Label((change.before == nil ? L("Create File") : L("Replace File")) + " · " + change.url.path, systemImage: "doc")
                                            .font(.caption).textSelection(.enabled)
                                    }
                                }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
                            }
                        }
                    }
                }
            }
            HStack {
                Button(L("Cancel")) { appState.queuePreview = nil }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(L("Confirm Writes")) { appState.confirmQueuePreview() }
                    .buttonStyle(.borderedProminent)
                    .disabled(preview.plans.isEmpty || !preview.errors.isEmpty)
            }
        }.padding(24).frame(width: 740, height: 600)
    }
}

struct WriteHistorySheet: View {
    @Environment(AppState.self) private var appState
    @State private var pendingUndo: UndoRecord?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L("Write History")).font(.title2.bold())
            Text(L("Write History Hint")).foregroundStyle(.secondary)
            if let error = appState.accessError {
                HStack(alignment: .top) {
                    Text(error).font(.callout).foregroundStyle(.red).textSelection(.enabled)
                    Spacer()
                    Button(L("OK")) { appState.accessError = nil }
                }
            }
            if appState.history.isEmpty {
                ContentUnavailableView(L("No Write History"), systemImage: "clock.arrow.circlepath")
            } else {
                List(appState.history) { record in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(record.plan.updated.fileName).font(.headline)
                            Text(record.date, format: .dateTime).font(.caption).foregroundStyle(.secondary)
                            if !record.completed { Text(L("Interrupted Write Hint")).font(.caption).foregroundStyle(.orange) }
                        }
                        Spacer()
                        Button(L("Undo Write")) { pendingUndo = record }.disabled(appState.isProcessingQueue)
                    }.padding(.vertical, 6)
                }
            }
            HStack { Spacer(); Button(L("Done")) { appState.showingHistory = false }.keyboardShortcut(.cancelAction) }
        }
        .padding(24).frame(width: 700, height: 500)
        .confirmationDialog(L("Undo Write"), isPresented: Binding(get: { pendingUndo != nil }, set: { if !$0 { pendingUndo = nil } })) {
            if let record = pendingUndo {
                Button(L("Undo Write"), role: .destructive) { appState.undoWrite(record); pendingUndo = nil }
            }
        } message: { Text(L("Undo Write Hint")) }
    }
}
