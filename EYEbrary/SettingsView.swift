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

private enum LibraryImportDestination {
    case activeLibrary
    case newLibrary
}

private extension UTType {
    static var eyeBraryLibraryPackage: UTType {
        UTType(exportedAs: "com.xbalsoftware.eyebrary.library", conformingTo: .package)
    }
}

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var showResetConfirm = false
    @State private var resetSuccessMessage: String?
    @State private var activeImportKind: ActiveImportKind?
    @State private var pendingImportKind: ActiveImportKind?
    @State private var letterheadImportErrorMessage: String?

    var body: some View {
        Form {
            Section("Library Management") {
                NavigationLink("Manage libraries") {
                    LibraryManagerView()
                }
            }

            Section("Categories") {
                NavigationLink("Edit categories") {
                    CategoryManagerView()
                }

                Text("Categories control the chips shown at the top of New Report and Manage Library.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

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
        .fileImporter(
            isPresented: Binding(
                get: { activeImportKind == .letterhead },
                set: { if !$0 { activeImportKind = nil } }
            ),
            allowedContentTypes: [.pdf],
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
                case .letterhead:
                    try store.addLetterhead(from: url)
                    pendingImportKind = nil
                case .library, .none:
                    pendingImportKind = nil
                }
            } catch {
                letterheadImportErrorMessage = error.localizedDescription
                pendingImportKind = nil
            }
        }
        .alert("Import Failed", isPresented: Binding(
            get: { letterheadImportErrorMessage != nil },
            set: { if !$0 { letterheadImportErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {
                letterheadImportErrorMessage = nil
            }
        } message: {
            Text(letterheadImportErrorMessage ?? "Unknown error")
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

}

private struct CategoryManagerView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var isEditing = false
    @State private var editingCategoryNames: [EntryCategory: String] = [:]
    @State private var showAddCategoryPrompt = false
    @State private var pendingNewCategoryName = ""
    @State private var pendingDeleteCategory: CategoryItem?

    var body: some View {
        List {
            ForEach(store.sortedCategories(), id: \.id) { category in
                HStack(spacing: 12) {
                    if isEditing, category.id != .general {
                        TextField(
                            "Category Name",
                            text: Binding(
                                get: { editingCategoryNames[category.id] ?? category.name },
                                set: { editingCategoryNames[category.id] = $0 }
                            )
                        )
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                    } else {
                        Text(category.name)
                            .foregroundStyle(category.id == .general ? .secondary : .primary)
                    }

                    Spacer()

                    if isEditing, category.id != .general {
                        Button(role: .destructive) {
                            pendingDeleteCategory = category
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
        }
        .navigationTitle("Categories")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(isEditing ? "Done" : "Edit") {
                    if isEditing {
                        commitCategoryRenames()
                    }
                    isEditing.toggle()
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    pendingNewCategoryName = ""
                    showAddCategoryPrompt = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .alert("Add Category", isPresented: $showAddCategoryPrompt) {
            TextField("Category Name", text: $pendingNewCategoryName)
            Button("Add") {
                store.addCategory(named: pendingNewCategoryName)
                pendingNewCategoryName = ""
            }
            Button("Cancel", role: .cancel) {
                pendingNewCategoryName = ""
            }
        } message: {
            Text("Create a new global category.")
        }
        .alert(
            "Delete category?",
            isPresented: Binding(
                get: { pendingDeleteCategory != nil },
                set: { if !$0 { pendingDeleteCategory = nil } }
            ),
            presenting: pendingDeleteCategory
        ) { category in
            Button("Delete", role: .destructive) {
                store.deleteCategory(id: category.id)
                editingCategoryNames[category.id] = nil
                pendingDeleteCategory = nil
            }
            Button("Cancel", role: .cancel) {
                pendingDeleteCategory = nil
            }
        } message: { category in
            let affectedCount = store.entries.filter { $0.category == category.id }.count
            Text(deleteConfirmationMessage(for: category.name, affectedCount: affectedCount))
        }
    }

    private func commitCategoryRenames() {
        for category in store.sortedCategories() where category.id != .general {
            if let proposedName = editingCategoryNames[category.id] {
                store.renameCategory(id: category.id, to: proposedName)
            }
        }
        editingCategoryNames.removeAll()
    }

    private func deleteConfirmationMessage(for categoryName: String, affectedCount: Int) -> String {
        if affectedCount == 0 {
            return "Delete \"\(categoryName)\"?"
        }

        let entryWord = affectedCount == 1 ? "entry is" : "entries are"
        return "Delete \"\(categoryName)\"? \(affectedCount) \(entryWord) currently assigned to this category and will be reassigned to General."
    }
}

private struct LibraryManagerView: View {
    @EnvironmentObject private var store: AppStore

    @AppStorage("EYEbrary.normalizeTextOnImport.v1") private var normalizeTextOnImport = true

    @State private var importErrorMessage: String?
    @State private var importInProgress = false
    @State private var pendingImportMode: TemplateImportMode?
    @State private var showImportModeDialog = false
    @State private var importSuccessMessage: String?
    @State private var activeImportKind: ActiveImportKind?
    @State private var pendingImportKind: ActiveImportKind?
    @State private var pendingImportDestination: LibraryImportDestination?

    @State private var isEditing = false
    @State private var editingLibraryNames: [UUID: String] = [:]
    @State private var showAddLibraryPrompt = false
    @State private var pendingNewLibraryName = ""
    @State private var pendingDeleteLibrary: LibraryCollection?
    @State private var editMode: EditMode = .inactive

    private var showingImportDestinationDialog: Binding<Bool> {
        Binding(
            get: { pendingImportDestination == nil && showImportModeDialog },
            set: { if !$0 { showImportModeDialog = false } }
        )
    }

    private var showingActiveLibraryImportModeDialog: Binding<Bool> {
        Binding(
            get: { pendingImportDestination == .activeLibrary && showImportModeDialog },
            set: { if !$0 { showImportModeDialog = false } }
        )
    }

    var body: some View {
        libraryManagerAlertsView
    }

    private var libraryManagerBaseView: some View {
        List {
            libraryListSection
            importSection
        }
        .navigationTitle("Libraries")
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.editMode, $editMode)
        .toolbar { libraryToolbar }
    }

    private var libraryManagerDialogsView: some View {
        libraryManagerBaseView
            .alert("Add Library", isPresented: $showAddLibraryPrompt) {
                TextField("Library Name", text: $pendingNewLibraryName)
                Button("Add") {
                    _ = store.createLibrary(named: pendingNewLibraryName)
                    pendingNewLibraryName = ""
                }
                Button("Cancel", role: .cancel) {
                    pendingNewLibraryName = ""
                }
            } message: {
                Text("Create a new empty library.")
            }
            .confirmationDialog("Import Library", isPresented: showingImportDestinationDialog, titleVisibility: .visible) {
                importDestinationDialogButtons
            } message: {
                Text("Choose whether to import into the active library or create a new library from the selected file.")
            }
            .confirmationDialog("Import into Active Library", isPresented: showingActiveLibraryImportModeDialog, titleVisibility: .visible) {
                activeLibraryImportModeDialogButtons
            } message: {
                Text("\"\(store.activeLibraryName)\" is currently active.")
            }
    }

    private var libraryManagerImporterView: some View {
        libraryManagerDialogsView
            .onChange(of: pendingImportMode) { _, newValue in
                guard newValue != nil else { return }
                guard pendingImportDestination == .activeLibrary else { return }
                DispatchQueue.main.async {
                    pendingImportKind = .library
                    activeImportKind = .library
                }
            }
            .fileImporter(
                isPresented: importerPresentedBinding,
                allowedContentTypes: activeImportKind == .letterhead ? [.pdf] : [.json, .eyeBraryLibraryPackage],
                allowsMultipleSelection: false,
                onCompletion: handleFileImportResult
            )
    }

    private var libraryManagerAlertsView: some View {
        libraryManagerImporterView
            .alert("Import Failed", isPresented: importFailedBinding) {
                Button("OK", role: .cancel) {
                    importErrorMessage = nil
                }
            } message: {
                Text(importErrorMessage ?? "Unknown error")
            }
            .alert("Import Complete", isPresented: importCompleteBinding) {
                Button("OK", role: .cancel) {
                    importSuccessMessage = nil
                }
            } message: {
                Text(importSuccessMessage ?? "")
            }
            .alert(
                "Delete library?",
                isPresented: deleteLibraryPresentedBinding,
                presenting: pendingDeleteLibrary
            ) { library in
                Button("Delete", role: .destructive) {
                    store.deleteLibrary(id: library.id)
                    editingLibraryNames[library.id] = nil
                    pendingDeleteLibrary = nil
                }
                Button("Cancel", role: .cancel) {
                    pendingDeleteLibrary = nil
                }
            } message: { library in
                Text(deleteConfirmationMessage(for: library))
            }
    }

    @ToolbarContentBuilder
    private var libraryToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button(isEditing ? "Done" : "Edit") {
                if isEditing {
                    commitLibraryRenames()
                    editMode = .inactive
                } else {
                    editMode = .active
                }
                isEditing.toggle()
            }
        }

        ToolbarItem(placement: .topBarTrailing) {
            Button {
                pendingNewLibraryName = ""
                showAddLibraryPrompt = true
            } label: {
                Image(systemName: "plus")
            }
        }
    }

    private var importerPresentedBinding: Binding<Bool> {
        Binding(
            get: { activeImportKind != nil },
            set: { if !$0 { activeImportKind = nil } }
        )
    }

    private var importFailedBinding: Binding<Bool> {
        Binding(
            get: { importErrorMessage != nil },
            set: { if !$0 { importErrorMessage = nil } }
        )
    }

    private var importCompleteBinding: Binding<Bool> {
        Binding(
            get: { importSuccessMessage != nil },
            set: { if !$0 { importSuccessMessage = nil } }
        )
    }

    private var deleteLibraryPresentedBinding: Binding<Bool> {
        Binding(
            get: { pendingDeleteLibrary != nil },
            set: { if !$0 { pendingDeleteLibrary = nil } }
        )
    }

    @ViewBuilder
    private var importDestinationDialogButtons: some View {
        Button("Import into Active Library") {
            pendingImportDestination = .activeLibrary
            showImportModeDialog = false
            DispatchQueue.main.async {
                showImportModeDialog = true
            }
        }
        Button("Import as New Library") {
            pendingImportDestination = .newLibrary
            pendingImportKind = .library
            activeImportKind = .library
            showImportModeDialog = false
        }
        Button("Cancel", role: .cancel) {
            pendingImportDestination = nil
            pendingImportMode = nil
        }
    }

    @ViewBuilder
    private var activeLibraryImportModeDialogButtons: some View {
        Button("Merge into Active Library") {
            pendingImportMode = .merge
            showImportModeDialog = false
        }
        Button("Replace Active Library", role: .destructive) {
            pendingImportMode = .replace
            showImportModeDialog = false
        }
        Button("Cancel", role: .cancel) {
            pendingImportDestination = nil
            pendingImportMode = nil
        }
    }

    private func handleFileImportResult(_ result: Result<[URL], Error>) {
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
                            pendingImportDestination = nil
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
                do {
                    try store.addLetterhead(from: url)
                    pendingImportKind = nil
                } catch {
                    importErrorMessage = error.localizedDescription
                    pendingImportKind = nil
                }

            case nil:
                if didStartAccessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }
        } catch {
            DispatchQueue.main.async {
                importErrorMessage = error.localizedDescription
                pendingImportKind = nil
                pendingImportMode = nil
                pendingImportDestination = nil
                importInProgress = false
            }
        }
    }

    private var libraryListSection: some View {
        Section {
            ForEach(store.sortedLibraries()) { library in
                libraryRow(for: library)
            }
            .onMove(perform: moveLibraries)
        }
    }

    private var importSection: some View {
        Section("Import") {
            Toggle("Normalize text on import", isOn: $normalizeTextOnImport)

            Button("Import Library") {
                pendingImportDestination = nil
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
        }
    }

    @ViewBuilder
    private func libraryRow(for library: LibraryCollection) -> some View {
        HStack(spacing: 12) {
            Button {
                store.setActiveLibrary(id: library.id)
            } label: {
                Image(systemName: library.id == store.activeLibrary?.id ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(Color.accentColor)
                    .font(.system(size: 20, weight: .regular))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                if isEditing {
                    TextField(
                        "Library Name",
                        text: Binding(
                            get: { editingLibraryNames[library.id] ?? library.name },
                            set: { editingLibraryNames[library.id] = $0 }
                        )
                    )
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                } else {
                    Text(library.name)
                }

                Text(libraryMetadataText(for: library))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 0) {
                Button {
                    exportLibrary(library)
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.borderless)

                if isEditing {
                    Spacer()
                        .frame(width: 20)

                    Button(role: .destructive) {
                        pendingDeleteLibrary = library
                    } label: {
                        Image(systemName: "trash")
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.borderless)
                    .padding(.trailing, 16)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            store.setActiveLibrary(id: library.id)
        }
    }

    private func handleLibraryImport(from url: URL) throws {
        let destination = pendingImportDestination ?? .activeLibrary

        switch destination {
        case .activeLibrary:
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
                    successMessage = "Merged \(importedCount) entr\(importedCount == 1 ? "y" : "ies") into \"\(store.activeLibraryName)\": \(addedCount) added, \(updatedCount) updated."
                case .replace:
                    successMessage = "Replaced \"\(store.activeLibraryName)\" with \(importedCount) entr\(importedCount == 1 ? "y" : "ies") from the selected package."
                }

                DispatchQueue.main.async {
                    importSuccessMessage = successMessage
                    pendingImportKind = nil
                    pendingImportMode = nil
                    pendingImportDestination = nil
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
                successMessage = "Merged \(incomingIDs.count) entr\(incomingIDs.count == 1 ? "y" : "ies") into \"\(store.activeLibraryName)\": \(addedCount) added, \(updatedCount) updated."
            case .replace:
                successMessage = "Replaced \"\(store.activeLibraryName)\" with \(importedEntries.count) entr\(importedEntries.count == 1 ? "y" : "ies")."
            }

            DispatchQueue.main.async {
                importSuccessMessage = successMessage
                pendingImportKind = nil
                pendingImportMode = nil
                pendingImportDestination = nil
            }

        case .newLibrary:
            let newLibraryName = importedLibraryName(from: url)
            _ = store.createLibrary(named: newLibraryName)

            if url.pathExtension.lowercased() == "eyebrarylib" {
                let manifestURL = url.appendingPathComponent("manifest.json")
                let manifestData = try Data(contentsOf: manifestURL)
                let manifest = try JSONDecoder.standard.decode(EyeBraryLibraryManifest.self, from: manifestData)
                let importedCount = manifest.entries.count

                try store.importEyeBraryLibraryPackage(from: url, merge: false)

                DispatchQueue.main.async {
                    importSuccessMessage = "Created new library \"\(store.activeLibraryName)\" with \(importedCount) entr\(importedCount == 1 ? "y" : "ies")."
                    pendingImportKind = nil
                    pendingImportMode = nil
                    pendingImportDestination = nil
                }
                return
            }

            let data = try Data(contentsOf: url)
            let importedEntries = try JSONDecoder.standard.decode([LibraryEntry].self, from: data)
            try store.importLibraryJSON(data, merge: false)

            DispatchQueue.main.async {
                importSuccessMessage = "Created new library \"\(store.activeLibraryName)\" with \(importedEntries.count) entr\(importedEntries.count == 1 ? "y" : "ies")."
                pendingImportKind = nil
                pendingImportMode = nil
                pendingImportDestination = nil
            }
        }
    }

    private func importedLibraryName(from url: URL) -> String {
        let baseName = url.deletingPathExtension().lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        return baseName.isEmpty ? "Imported Library" : baseName
    }

    private func exportLibrary(_ library: LibraryCollection) {
        let previousActiveLibraryID = store.activeLibrary?.id

        do {
            if previousActiveLibraryID != library.id {
                store.setActiveLibrary(id: library.id)
            }

            let url = try store.makeTemporaryEyeBraryLibraryPackage(libraryName: library.name)

            if let previousActiveLibraryID, previousActiveLibraryID != library.id {
                store.setActiveLibrary(id: previousActiveLibraryID)
            }

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
            if let previousActiveLibraryID, previousActiveLibraryID != library.id {
                store.setActiveLibrary(id: previousActiveLibraryID)
            }
            importErrorMessage = error.localizedDescription
        }
    }

    private func moveLibraries(from source: IndexSet, to destination: Int) {
        var reordered = store.libraries
        reordered.move(fromOffsets: source, toOffset: destination)
        store.libraries = reordered
    }

    private func libraryMetadataText(for library: LibraryCollection) -> String {
        let entryCountText = "\(library.entries.count) entr\(library.entries.count == 1 ? "y" : "ies")"
        let createdText = "Created \(libraryDateText(library.createdAt))"
        let updatedText = "Updated \(libraryDateText(library.updatedAt))"
        return "\(entryCountText) • \(createdText) • \(updatedText)"
    }

    private func libraryDateText(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .omitted)
    }

    private func commitLibraryRenames() {
        for library in store.sortedLibraries() {
            if let proposedName = editingLibraryNames[library.id] {
                store.renameLibrary(id: library.id, to: proposedName)
            }
        }
        editingLibraryNames.removeAll()
    }

    private func deleteConfirmationMessage(for library: LibraryCollection) -> String {
        let entryCount = library.entries.count
        if store.sortedLibraries().count == 1 {
            return "Delete \"\(library.name)\"? A new empty Default Library will be created automatically."
        }
        return "Delete \"\(library.name)\"? This library contains \(entryCount) entr\(entryCount == 1 ? "y" : "ies")."
    }
}
