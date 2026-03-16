//
//  SettingsView.swift
//  EYEbrary
//
//  Created by Simon Reid on 2026-03-15.
//

import SwiftUI
import UIKit
import UniformTypeIdentifiers

private enum TemplateImportMode: String, CaseIterable, Identifiable {
    case merge
    case replace

    var id: String { rawValue }

    var title: String {
        switch self {
        case .merge:
            return "Merge into Current Library"
        case .replace:
            return "Replace Current Library"
        }
    }
}

private enum ActiveImportKind {
    case library
    case letterhead
}

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var importErrorMessage: String?
    @State private var showResetConfirm = false
    @State private var pendingImportMode: TemplateImportMode?
    @State private var showImportModeDialog = false
    @State private var importSuccessMessage: String?
    @State private var activeImportKind: ActiveImportKind?
    @State private var pendingImportKind: ActiveImportKind?

    var body: some View {
        Form {
            Section("Letterhead") {
                if let selected = store.selectedLetterheadName {
                    Text("Selected: \(selected)")
                } else {
                    Text("Selected: Blank (Built-in)")
                }

                Button("Import Letterhead PDF") {
                    pendingImportKind = .letterhead
                    activeImportKind = .letterhead
                }

                if !store.letterheads.isEmpty {
                    ForEach(store.letterheads, id: \.self) { name in
                        HStack {
                            Button {
                                store.selectedLetterheadName = name
                            } label: {
                                HStack {
                                    Text(name)
                                    Spacer()
                                    if store.selectedLetterheadName == name {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.tint)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            Section("Library") {
                Button("Import Library") {
                    showImportModeDialog = true
                }

                Button("Export Library") {
                    exportTemplates()
                }
            }

            Section("Reset") {
                Button("Reset App to Factory Defaults", role: .destructive) {
                    showResetConfirm = true
                }
            }
        }
        .navigationTitle("Settings")
        .confirmationDialog("Import Library", isPresented: $showImportModeDialog, titleVisibility: .visible) {
            Button(TemplateImportMode.merge.title) {
                pendingImportMode = .merge
                showImportModeDialog = false
            }
            Button(TemplateImportMode.replace.title, role: .destructive) {
                pendingImportMode = .replace
                showImportModeDialog = false
            }
            Button("Cancel", role: .cancel) {
                pendingImportMode = nil
            }
        } message: {
            Text("Choose how to import the selected library file.")
        }
        .onChange(of: pendingImportMode) { _, newValue in
            guard newValue != nil else { return }
            DispatchQueue.main.async {
                pendingImportKind = .library
                activeImportKind = .library
            }
        }
        .fileImporter(
            isPresented: Binding(
                get: { activeImportKind != nil },
                set: { if !$0 { activeImportKind = nil } }
            ),
            allowedContentTypes: activeImportKind == .letterhead ? [.pdf] : [.json],
            allowsMultipleSelection: false
        ) { result in
            let importKind = pendingImportKind
            activeImportKind = nil

            do {
                let urls = try result.get()
                guard let url = urls.first else { return }

                let didStartAccessing = url.startAccessingSecurityScopedResource()
                defer {
                    if didStartAccessing {
                        url.stopAccessingSecurityScopedResource()
                    }
                }

                switch importKind {
                case .library:
                    try handleLibraryImport(from: url)

                case .letterhead:
                    try store.addLetterhead(from: url)
                    pendingImportKind = nil

                case nil:
                    break
                }
            } catch {
                DispatchQueue.main.async {
                    importErrorMessage = error.localizedDescription
                    pendingImportKind = nil
                    if importKind == .library {
                        pendingImportMode = nil
                    }
                }
            }
        }
        .alert("Import Failed", isPresented: Binding(
            get: { importErrorMessage != nil },
            set: { if !$0 { importErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {
                importErrorMessage = nil
            }
        } message: {
            Text(importErrorMessage ?? "Unknown error")
        }
        .alert("Import Complete", isPresented: Binding(
            get: { importSuccessMessage != nil },
            set: { if !$0 { importSuccessMessage = nil } }
        )) {
            Button("OK", role: .cancel) {
                importSuccessMessage = nil
            }
        } message: {
            Text(importSuccessMessage ?? "")
        }
        .alert("Reset everything?", isPresented: $showResetConfirm) {
            Button("Reset", role: .destructive) {
                store.resetToFactoryDefaults()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove custom templates, categories, letterheads, and saved history.")
        }
    }

    private func handleLibraryImport(from url: URL) throws {
        let data = try Data(contentsOf: url)
        let mode = pendingImportMode ?? .merge
        let importedEntries = try JSONDecoder.standard.decode([LibraryEntry].self, from: data)

        let existingIDs = Set(store.entries.map { $0.id })
        let incomingIDs = Set(importedEntries.map { $0.id })
        let addedCount = incomingIDs.subtracting(existingIDs).count
        let updatedCount = incomingIDs.intersection(existingIDs).count

        try store.importLibraryJSON(data, merge: mode == .merge)

        let successMessage: String
        switch mode {
        case .merge:
            successMessage = "Merged \(incomingIDs.count) entr\(incomingIDs.count == 1 ? "y" : "ies"): \(addedCount) added, \(updatedCount) updated."
        case .replace:
            successMessage = "Replaced the current library with \(importedEntries.count) entr\(importedEntries.count == 1 ? "y" : "ies")."
        }

        DispatchQueue.main.async {
            importSuccessMessage = successMessage
            pendingImportKind = nil
            pendingImportMode = nil
        }
    }

    private func exportTemplates() {
        do {
            let data = try store.exportLibraryJSON()
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("EYEbrary Library.json")
            try data.write(to: url, options: .atomic)
            let av = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let controller = scene.windows.first?.rootViewController {
                if let popover = av.popoverPresentationController {
                    popover.sourceView = controller.view
                    popover.sourceRect = CGRect(
                        x: controller.view.bounds.midX,
                        y: controller.view.bounds.midY,
                        width: 1,
                        height: 1
                    )
                    popover.permittedArrowDirections = []
                }
                controller.present(av, animated: true)
            }
        } catch {
            importErrorMessage = error.localizedDescription
        }
    }
}
