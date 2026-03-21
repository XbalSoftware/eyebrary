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

private extension UTType {
    static var eyeBraryLibraryPackage: UTType {
        UTType(exportedAs: "com.xbalsoftware.eyebrary.library", conformingTo: .package)
    }
}

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var importErrorMessage: String?
    @State private var importInProgress = false
    @State private var showResetConfirm = false
    @State private var resetSuccessMessage: String?
    @State private var pendingImportMode: TemplateImportMode?
    @State private var showImportModeDialog = false
    @State private var importSuccessMessage: String?
    @State private var activeImportKind: ActiveImportKind?
    @State private var pendingImportKind: ActiveImportKind?

    var body: some View {
        Form {
            Section("Letterhead") {
                Button("Import Letterhead PDF") {
                    pendingImportKind = .letterhead
                    activeImportKind = .letterhead
                }

                if !store.letterheads.isEmpty {
                    ForEach(store.letterheads, id: \.self) { name in
                        Button {
                            store.selectedLetterheadName = name
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: store.selectedLetterheadName == name ? "largecircle.fill.circle" : "circle")
                                    .foregroundStyle(.tint)

                                Text(name)

                                Spacer()
                            }
                            .padding(.leading, 12)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Section("Library") {
                Button("Import Library") {
                    showImportModeDialog = true
                }
                .disabled(importInProgress)

                if importInProgress {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Importing library…")
                            .foregroundStyle(.secondary)
                    }
                }

                Button("Export Library") {
                    exportTemplates()
                }
            }

            Section {
                NavigationLink("About EYEbrary") {
                    AboutView()
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
            allowedContentTypes: activeImportKind == .letterhead ? [.pdf] : [.json, .eyeBraryLibraryPackage],
            allowsMultipleSelection: false
        ) { result in
            let importKind = pendingImportKind
            activeImportKind = nil

            do {
                let urls = try result.get()
                guard let url = urls.first else { return }

                let didStartAccessing = url.startAccessingSecurityScopedResource()

                switch importKind {
                case .library:
                    importInProgress = true
                    Task {
                        defer {
                            if didStartAccessing {
                                url.stopAccessingSecurityScopedResource()
                            }
                        }
                        do {
                            try handleLibraryImport(from: url)
                        } catch {
                            await MainActor.run {
                                importErrorMessage = error.localizedDescription
                                pendingImportKind = nil
                                pendingImportMode = nil
                            }
                        }
                        await MainActor.run {
                            importInProgress = false
                        }
                    }

                case .letterhead:
                    defer {
                        if didStartAccessing {
                            url.stopAccessingSecurityScopedResource()
                        }
                    }
                    try store.addLetterhead(from: url)
                    pendingImportKind = nil

                case nil:
                    if didStartAccessing {
                        url.stopAccessingSecurityScopedResource()
                    }
                    break
                }
            } catch {
                DispatchQueue.main.async {
                    importErrorMessage = error.localizedDescription
                    pendingImportKind = nil
                    pendingImportMode = nil
                    importInProgress = false
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
                resetSuccessMessage = "EYEbrary has been restored to factory defaults."
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove custom templates, categories, letterheads, and saved history.")
        }
        .alert("Reset Complete", isPresented: Binding(
            get: { resetSuccessMessage != nil },
            set: { if !$0 { resetSuccessMessage = nil } }
        )) {
            Button("OK", role: .cancel) {
                resetSuccessMessage = nil
            }
        } message: {
            Text(resetSuccessMessage ?? "")
        }
    }

    private func handleLibraryImport(from url: URL) throws {
        let mode = pendingImportMode ?? .merge

        if url.pathExtension.lowercased() == "eyebrarylib" {
            let manifestURL = url.appendingPathComponent("manifest.json")
            let manifestData = try Data(contentsOf: manifestURL)
            let manifest = try JSONDecoder.standard.decode(EyeBraryLibraryManifest.self, from: manifestData)
            let importedCount = manifest.entries.count
            let incomingIDs = Set(manifest.entries.map { $0.id })
            let existingIDs = Set(store.entries.map { $0.id })
            let addedCount = incomingIDs.subtracting(existingIDs).count
            let updatedCount = incomingIDs.intersection(existingIDs).count

            try store.importEyeBraryLibraryPackage(from: url, merge: mode == .merge)

            let successMessage: String
            switch mode {
            case .merge:
                successMessage = "Merged \(importedCount) entr\(importedCount == 1 ? "y" : "ies"): \(addedCount) added, \(updatedCount) updated."
            case .replace:
                successMessage = "Replaced the current library with \(importedCount) entr\(importedCount == 1 ? "y" : "ies") from the selected package."
            }

            DispatchQueue.main.async {
                importSuccessMessage = successMessage
                pendingImportKind = nil
                pendingImportMode = nil
            }
            return
        }

        let data = try Data(contentsOf: url)
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
            let url = try store.makeTemporaryEyeBraryLibraryPackage(libraryName: "EYEbrary Library")
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
