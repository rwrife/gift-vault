import GiftVaultKit
import GiftVaultStoreKit
import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: - Settings → Backup (issue #6)
//
// Export the versioned JSON bundle and CSV views via the system share
// sheet; restore via the file picker. No network — files are written to a
// temporary directory and handed to `UIActivityViewController`/
// `fileImporter`, both share-sheet/file-picker based per the product
// contract.

struct SettingsView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("Backup") {
                    NavigationLink("Backup") {
                        BackupView()
                    }
                }
            }
            .navigationTitle("Settings")
            .accessibilityIdentifier("screen.settings")
        }
    }
}

struct BackupView: View {
    @EnvironmentObject private var model: GiftVaultAppModel

    @State private var shareItems: [URL]?
    @State private var showingRestorePicker = false
    @State private var toast: BackupToast?

    struct BackupToast: Identifiable {
        let id = UUID()
        let message: String
        let isError: Bool
    }

    var body: some View {
        List {
            Section("Export") {
                Button("Export bundle") {
                    exportBundle()
                }
                .accessibilityIdentifier("backup.exportBundle")

                Button("Export ideas CSV") {
                    exportCSV(named: "gift-vault-ideas.csv") { model.exportIdeasCSV() }
                }
                .accessibilityIdentifier("backup.exportIdeasCSV")

                Button("Export occasions CSV") {
                    exportCSV(named: "gift-vault-occasions.csv") { model.exportOccasionsCSV() }
                }
                .accessibilityIdentifier("backup.exportOccasionsCSV")

                Button("Export ledger CSV") {
                    exportCSV(named: "gift-vault-ledger.csv") { model.exportLedgerCSV() }
                }
                .accessibilityIdentifier("backup.exportLedgerCSV")
            }

            Section("Restore") {
                Button("Restore from bundle") {
                    showingRestorePicker = true
                }
                .accessibilityIdentifier("backup.restore")
                Text("Restoring replaces everything currently in this vault with the backup's contents.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Backup")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: Binding(
            get: { shareItems.map(ShareURLs.init) },
            set: { newValue in shareItems = newValue?.urls }
        )) { wrapped in
            ActivityShareSheet(items: wrapped.urls)
        }
        .fileImporter(
            isPresented: $showingRestorePicker,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            handleRestoreSelection(result)
        }
        .alert(item: $toast) { toast in
            Alert(
                title: Text(toast.isError ? "Export/Restore failed" : "Success"),
                message: Text(toast.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .accessibilityIdentifier("screen.backup")
    }

    private struct ShareURLs: Identifiable {
        let urls: [URL]
        var id: String { urls.map(\.path).joined(separator: "|") }
    }

    private func exportBundle() {
        guard let data = model.exportBundleData() else {
            toast = BackupToast(message: model.lastError ?? "Export failed", isError: true)
            return
        }
        guard let url = writeTemp(data: data, filename: "gift-vault-backup.json") else {
            toast = BackupToast(message: "Could not write backup file", isError: true)
            return
        }
        shareItems = [url]
    }

    private func exportCSV(named filename: String, _ body: () -> String?) {
        guard let text = body() else {
            toast = BackupToast(message: model.lastError ?? "Export failed", isError: true)
            return
        }
        guard let data = text.data(using: .utf8),
              let url = writeTemp(data: data, filename: filename) else {
            toast = BackupToast(message: "Could not write CSV file", isError: true)
            return
        }
        shareItems = [url]
    }

    private func writeTemp(data: Data, filename: String) -> URL? {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GiftVaultExports", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent(filename)
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    private func handleRestoreSelection(_ result: Result<[URL], Error>) {
        switch result {
        case let .failure(error):
            toast = BackupToast(message: "Could not open file: \(error.localizedDescription)", isError: true)
        case let .success(urls):
            guard let url = urls.first else { return }
            let didAccess = url.startAccessingSecurityScopedResource()
            defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                if model.restoreBundle(data: data) {
                    toast = BackupToast(message: "Vault restored from backup.", isError: false)
                } else {
                    toast = BackupToast(message: model.lastError ?? "Restore failed", isError: true)
                }
            } catch {
                toast = BackupToast(message: "Could not read file: \(error.localizedDescription)", isError: true)
            }
        }
    }
}

/// Thin `UIActivityViewController` wrapper for the system share sheet.
private struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [URL]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
