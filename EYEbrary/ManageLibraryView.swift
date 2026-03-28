//
//  ManageLibraryView.swift
//  EYEbrary
//
//  Created by Simon Reid on 2026-03-15.
//
import SwiftUI
import Foundation
import Combine

// MARK: - Manage Library

struct ManageLibraryView: View {
    @EnvironmentObject private var store: AppStore

    @State private var query: String = ""
    @State private var categoryFilter: CategoryFilter = .all
    @State private var favoriteEditMode: Bool = false
    @State private var selectedID: UUID? = nil
    @State private var pendingDeleteEntryID: UUID? = nil
    @State private var showDeleteEntryConfirm: Bool = false
    @State private var detailIsEditing: Bool = false
    @State private var detailHasUnsavedChanges: Bool = false
    @State private var pendingSelectionID: UUID? = nil
    @State private var pendingCreateNewEntry: Bool = false
    @State private var autoStartEditingEntryID: UUID? = nil
    @State private var draftNewEntryID: UUID? = nil
    @State private var showDiscardChangesAlert: Bool = false
    @State private var showRecentlyImportedSheet: Bool = false

    private var currentSortMode: LibrarySortMode {
        store.sortMode()
    }

    private var canManuallyReorder: Bool {
        currentSortMode == .manual && query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var filtered: [LibraryEntry] {
        let base = store.entries.filter { matchesCategory($0, filter: categoryFilter) }
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)

        let searchFiltered: [LibraryEntry]
        if q.isEmpty {
            searchFiltered = base
        } else {
            searchFiltered = base.filter {
                $0.title.localizedCaseInsensitiveContains(q) ||
                $0.body.localizedCaseInsensitiveContains(q)
            }
        }

        return sortedEntries(searchFiltered, query: q)
    }

    private var hiddenCount: Int {
        filtered.filter { !$0.isVisible }.count
    }

    private var selectedEntry: LibraryEntry? {
        guard let id = selectedID else { return nil }
        return store.entry(id: id)
    }

    private var orderedCategories: [CategoryItem] {
        store.categories.sorted { $0.order < $1.order }
    }

    private var nonGeneralCategories: [CategoryItem] {
        orderedCategories.filter { ( $0.id.isEmpty ? EntryCategory.general : $0.id ) != .general }
    }

    private func sortedEntries(_ entries: [LibraryEntry], query: String) -> [LibraryEntry] {
        entries.sorted { a, b in
            if !query.isEmpty {
                let aTitleMatch = a.title.localizedCaseInsensitiveContains(query)
                let bTitleMatch = b.title.localizedCaseInsensitiveContains(query)
                if aTitleMatch != bTitleMatch {
                    return aTitleMatch && !bTitleMatch
                }
            }

            switch currentSortMode {
            case .manual:
                let ao = a.order ?? Int.max
                let bo = b.order ?? Int.max
                if ao != bo { return ao < bo }
                return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending

            case .alphabeticalAZ:
                return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending

            case .alphabeticalZA:
                return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedDescending

            case .newestUpdated:
                if a.updatedAt != b.updatedAt { return a.updatedAt > b.updatedAt }
                return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending

            case .oldestUpdated:
                if a.updatedAt != b.updatedAt { return a.updatedAt < b.updatedAt }
                return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
            }
        }
    }

    private var sortModeDisplayName: String {
        switch currentSortMode {
        case .manual:
            return "Manual"
        case .alphabeticalAZ:
            return "A–Z"
        case .alphabeticalZA:
            return "Z–A"
        case .newestUpdated:
            return "Newest"
        case .oldestUpdated:
            return "Oldest"
        }
    }

    var body: some View {
        NavigationSplitView {
            manageSidebar
                .navigationSplitViewColumnWidth(
                    min: 280,
                    ideal: 360,
                    max: 420
                )
        } detail: {
            manageDetail
        }
        .navigationTitle("Manage Library")
        .onChange(of: store.activeLibraryID) { _, _ in
            selectedID = nil
        }
        .sheet(isPresented: $showRecentlyImportedSheet) {
            NavigationStack {
                BatchSelectSheet()
            }
            .environmentObject(store)
            .presentationDetents([.large])
            .interactiveDismissDisabled()
        }
        .alert("Delete entry?", isPresented: $showDeleteEntryConfirm) {
            Button("Delete", role: .destructive) {
                if let id = pendingDeleteEntryID {
                    store.deleteEntries(withIDs: [id])
                    if selectedID == id { selectedID = nil }
                }
                pendingDeleteEntryID = nil
            }
            Button("Cancel", role: .cancel) {
                pendingDeleteEntryID = nil
            }
        } message: {
            Text("This will permanently delete the entry.")
        }
        .alert("Discard unsaved changes?", isPresented: $showDiscardChangesAlert) {
            Button("Discard Changes", role: .destructive) {
                let currentDraftID = draftNewEntryID

                if let draftID = currentDraftID {
                    store.entries.removeAll { $0.id == draftID }
                    if selectedID == draftID {
                        selectedID = nil
                    }
                    draftNewEntryID = nil
                    autoStartEditingEntryID = nil
                }

                if pendingCreateNewEntry {
                    createNewEntryAndStartEditing()
                } else if let pending = pendingSelectionID {
                    selectedID = pending
                }
                pendingSelectionID = nil
                pendingCreateNewEntry = false
                detailIsEditing = false
                detailHasUnsavedChanges = false
            }
            Button("Cancel", role: .cancel) {
                pendingSelectionID = nil
                pendingCreateNewEntry = false
            }
        } message: {
            Text("Any unsaved changes will be lost if you leave this entry without saving.")
        }
    }

    private var manageSidebar: some View {
        VStack(spacing: 12) {
            manageHeader
            if favoriteEditMode {
                Text("Tap stars to edit favorites")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal)
            }
            manageCategoryChips
            manageSearch
            manageEntriesList

            HStack(spacing: 6) {
                Text("\(filtered.count) \(filtered.count == 1 ? "entry" : "entries")")

                if hiddenCount > 0 {
                    Text("(\(hiddenCount) hidden)")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.footnote)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 4)
        }
        .padding(.bottom, 8)
    }

    private var manageHeader: some View {
        HStack(spacing: 12) {
            Button {
                favoriteEditMode.toggle()
            } label: {
                Image(systemName: favoriteEditMode ? "star.fill" : "star")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(favoriteEditMode ? Color.yellow : Color.secondary)
            }
            .buttonStyle(.plain)
            .frame(width: 24, alignment: .center)
            .padding(.leading, 6)

            Menu {
                ForEach(store.sortedLibraries()) { library in
                    Button {
                        store.setActiveLibrary(id: library.id)
                    } label: {
                        if library.id == store.activeLibrary?.id {
                            Label(library.name, systemImage: "checkmark")
                        } else {
                            Text(library.name)
                        }
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Text(store.activeLibraryName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.center)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .center)

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: 280)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.secondary.opacity(0.12))
                )
            }
            .buttonStyle(.plain)

            Button {
                if detailIsEditing && detailHasUnsavedChanges {
                    pendingSelectionID = nil
                    pendingCreateNewEntry = true
                    showDiscardChangesAlert = true
                } else {
                    createNewEntryAndStartEditing()
                }
            } label: {
                Label("New Entry", systemImage: "plus")
                    .labelStyle(.iconOnly)
                    .font(.system(size: 18, weight: .semibold))
            }
            .buttonStyle(.plain)
            .frame(width: 24, alignment: .center)
            .padding(.trailing, 6)
        }
    }


    private var manageCategoryChips: some View {
        HStack(spacing: 10) {
            if categoryFilter != .all {
                Button {
                    categoryFilter = .all
                } label: {
                    Text("All")
                        .font(.footnote)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.secondary.opacity(0.12))
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("All Categories")
            }

            Menu {
                Button {
                    categoryFilter = .all
                } label: {
                    if categoryFilter == .all {
                        Label("All Categories", systemImage: "checkmark")
                    } else {
                        Text("All Categories")
                    }
                }

                Divider()

                ForEach(orderedCategories) { item in
                    let cat: EntryCategory = item.id.isEmpty ? .general : item.id
                    Button {
                        categoryFilter = .category(cat)
                    } label: {
                        if categoryFilter == .category(cat) {
                            Label(item.name, systemImage: "checkmark")
                        } else {
                            Text(item.name)
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(categoryFilter.displayName(using: store))
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .font(.footnote)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.secondary.opacity(0.12))
                )
            }
            .buttonStyle(.plain)

            Menu {
                Button {
                    store.setSortMode(.manual)
                } label: {
                    if currentSortMode == .manual {
                        Label("Manual", systemImage: "checkmark")
                    } else {
                        Text("Manual")
                    }
                }

                Button {
                    store.setSortMode(.alphabeticalAZ)
                } label: {
                    if currentSortMode == .alphabeticalAZ {
                        Label("A–Z", systemImage: "checkmark")
                    } else {
                        Text("A–Z")
                    }
                }

                Button {
                    store.setSortMode(.alphabeticalZA)
                } label: {
                    if currentSortMode == .alphabeticalZA {
                        Label("Z–A", systemImage: "checkmark")
                    } else {
                        Text("Z–A")
                    }
                }

                Button {
                    store.setSortMode(.newestUpdated)
                } label: {
                    if currentSortMode == .newestUpdated {
                        Label("Newest Updated", systemImage: "checkmark")
                    } else {
                        Text("Newest Updated")
                    }
                }

                Button {
                    store.setSortMode(.oldestUpdated)
                } label: {
                    if currentSortMode == .oldestUpdated {
                        Label("Oldest Updated", systemImage: "checkmark")
                    } else {
                        Text("Oldest Updated")
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(sortModeDisplayName)
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .font(.footnote)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.secondary.opacity(0.12))
                )
            }
            .buttonStyle(.plain)

            Button {
                showRecentlyImportedSheet = true
            } label: {
                Image(systemName: "checklist")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.secondary.opacity(0.12))
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Batch Select")
        }
        .padding(.horizontal)
        .padding(.top, 2)
    }

    private var manageSearch: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Search", text: $query)
                .textFieldStyle(.plain)
                .autocorrectionDisabled(true)

            if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.secondary.opacity(0.15))
        )
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private var manageEntriesList: some View {
        List {
            if filtered.isEmpty {
                ContentUnavailableView(
                    "No entries",
                    systemImage: "doc.text",
                    description: Text("Tap + to add a library entry.")
                )
                .listRowBackground(Color.clear)
            } else {
                ForEach(filtered) { t in
                    manageEntryRow(t)
                        .listRowBackground(
                            selectedID == t.id
                            ? Color.accentColor.opacity(0.16)
                            : Color.clear
                        )
                        .moveDisabled(!canManuallyReorder)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                pendingDeleteEntryID = t.id
                                showDeleteEntryConfirm = true
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
                .onMove(perform: handleMove)
            }
        }
    }

    @ViewBuilder
    private func manageEntryRow(_ t: LibraryEntry) -> some View {
        HStack(spacing: 10) {
            Text(t.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled Entry" : t.title)
                .font(.subheadline)
                .lineLimit(2)
                .layoutPriority(1)
                .foregroundStyle(t.isVisible ? Color.primary : Color.red)

            Spacer(minLength: 0)

            if favoriteEditMode {
                Button {
                    store.toggleFavorite(id: t.id)
                } label: {
                    Image(systemName: t.isFavorite ? "star.fill" : "star")
                        .foregroundStyle(t.isFavorite ? Color.yellow : Color.secondary)
                }
                .buttonStyle(.plain)
            } else if t.isFavorite {
                Image(systemName: "star.fill")
                    .foregroundStyle(Color.yellow)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard selectedID != t.id else { return }

            // Always treat draft entries as having unsaved changes
            if draftNewEntryID != nil || (detailIsEditing && detailHasUnsavedChanges) {
                pendingSelectionID = t.id
                showDiscardChangesAlert = true
            } else {
                selectedID = t.id
            }
        }
    }

    private func handleMove(from source: IndexSet, to destination: Int) {
        guard canManuallyReorder else { return }

        var ids = filtered.map { $0.id }
        ids.move(fromOffsets: source, toOffset: destination)
        store.applyReorder(orderedIDs: ids)
    }



    private var manageDetail: some View {
        Group {
            if let t = selectedEntry {
                ManageEntryDetail(
                    selectedID: $selectedID,
                    isEditingExternal: $detailIsEditing,
                    hasUnsavedChangesExternal: $detailHasUnsavedChanges,
                    autoStartEditingEntryID: $autoStartEditingEntryID,
                    draftNewEntryID: $draftNewEntryID,
                    entry: t
                )
            } else {
                ContentUnavailableView(
                    "Select an entry",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("Choose a library entry from the left to edit it.")
                )
            }
        }
    }

    private func createNewEntryAndStartEditing() {
        let newID = UUID()
        let entry = LibraryEntry(
            id: newID,
            title: "",
            body: "",
            category: .general,
            isFavorite: false,
            isVisible: true,
            order: ((store.entries.compactMap { $0.order }.min() ?? 0) - 1),
            createdAt: Date(),
            updatedAt: Date()
        )
        store.addEntry(entry)
        selectedID = newID
        autoStartEditingEntryID = newID
        draftNewEntryID = newID
        pendingCreateNewEntry = false
    }
    // removed createNewTemplate()

    private func changeCategory(for ids: [UUID], to newCategory: EntryCategory) {
        store.updateEntryCategories(ids: Set(ids), to: newCategory)
    }
}

private struct ImportedEntryGroup: Identifiable {
    let id: Date
    let importedAt: Date
    var entries: [LibraryEntry]
}

private enum BatchSelectArrangeMode: String, CaseIterable {
    case manual
    case alphabeticalAZ
    case alphabeticalZA
    case newestUpdated
    case oldestUpdated
    case recentImports
}

private struct BatchSelectSheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var isSelecting = false
    @State private var selectedEntryIDs: Set<UUID> = []
    @State private var showCategoryDialog = false
    @State private var showDeleteConfirmation = false
    @State private var shareItem: ShareItem? = nil
    @State private var exportErrorMessage: String? = nil
    @State private var query: String = ""
    @State private var arrangeMode: BatchSelectArrangeMode = .recentImports
    @State private var showSelectedOnly: Bool = false

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var searchableEntries: [LibraryEntry] {
        let base = store.entries
        guard !trimmedQuery.isEmpty else { return base }
        return base.filter {
            $0.title.localizedCaseInsensitiveContains(trimmedQuery) ||
            $0.body.localizedCaseInsensitiveContains(trimmedQuery)
        }
    }
    private var arrangedEntriesSource: [LibraryEntry] {
        let base = searchableEntries
        guard showSelectedOnly else { return base }
        return base.filter { selectedEntryIDs.contains($0.id) }
    }
    private var flatEntries: [LibraryEntry] {
        arrangedEntriesSource.sorted { a, b in
            if !trimmedQuery.isEmpty {
                let aTitleMatch = a.title.localizedCaseInsensitiveContains(trimmedQuery)
                let bTitleMatch = b.title.localizedCaseInsensitiveContains(trimmedQuery)
                if aTitleMatch != bTitleMatch {
                    return aTitleMatch && !bTitleMatch
                }
            }

            switch arrangeMode {
            case .manual:
                let ao = a.order ?? Int.max
                let bo = b.order ?? Int.max
                if ao != bo { return ao < bo }
                return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending

            case .alphabeticalAZ:
                return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending

            case .alphabeticalZA:
                return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedDescending

            case .newestUpdated:
                if a.updatedAt != b.updatedAt { return a.updatedAt > b.updatedAt }
                return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending

            case .oldestUpdated:
                if a.updatedAt != b.updatedAt { return a.updatedAt < b.updatedAt }
                return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending

            case .recentImports:
                let aDate = a.lastImportedAt ?? .distantPast
                let bDate = b.lastImportedAt ?? .distantPast
                if aDate != bDate { return aDate > bDate }
                return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
            }
        }
    }

    private var importedGroups: [ImportedEntryGroup] {
        let importedEntries = flatEntries.filter { $0.lastImportedAt != nil }

        var groups: [ImportedEntryGroup] = []
        for entry in importedEntries {
            guard let importedAt = entry.lastImportedAt else { continue }
            if let lastIndex = groups.indices.last, groups[lastIndex].importedAt == importedAt {
                groups[lastIndex].entries.append(entry)
            } else {
                groups.append(ImportedEntryGroup(id: importedAt, importedAt: importedAt, entries: [entry]))
            }
        }
        return groups
    }

    private var arrangeDisplayName: String {
        switch arrangeMode {
        case .manual:
            return "Manual"
        case .alphabeticalAZ:
            return "A–Z"
        case .alphabeticalZA:
            return "Z–A"
        case .newestUpdated:
            return "Newest"
        case .oldestUpdated:
            return "Oldest"
        case .recentImports:
            return "Recent Imports"
        }
    }

    var body: some View {
        VStack(spacing: 10) {
            searchAndArrangeBar
            if isSelecting {
                selectionStatusBar
            }
            Group {
                if arrangeMode == .recentImports {
                    if importedGroups.isEmpty {
                        ContentUnavailableView(
                            "No imported entries",
                            systemImage: "clock.arrow.circlepath",
                            description: Text("Imported entries from the active library will appear here.")
                        )
                    } else {
                        importedGroupsList
                    }
                } else {
                    if flatEntries.isEmpty {
                        ContentUnavailableView(
                            "No matching entries",
                            systemImage: "checklist",
                            description: Text("Try a different search or arrange mode.")
                        )
                    } else {
                        flatEntriesList
                    }
                }
            }
        }
        .navigationTitle("Batch Select")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Done") {
                    dismiss()
                }
            }

            ToolbarItemGroup(placement: .topBarTrailing) {
                if isSelecting {
                    Button("Export") {
                        exportSelectedEntries()
                    }
                    .disabled(selectedEntryIDs.isEmpty)

                    Button("Category") {
                        showCategoryDialog = true
                    }
                    .disabled(selectedEntryIDs.isEmpty)

                    Button("Delete", role: .destructive) {
                        showDeleteConfirmation = true
                    }
                    .disabled(selectedEntryIDs.isEmpty)

                    Button("Cancel") {
                        isSelecting = false
                        selectedEntryIDs.removeAll()
                        showSelectedOnly = false
                    }
                } else {
                    Button("Select") {
                        isSelecting = true
                    }
                }
            }
        }
        .confirmationDialog("Apply Category", isPresented: $showCategoryDialog, titleVisibility: .visible) {
            ForEach(store.sortedCategories(), id: \.id) { item in
                let categoryID: EntryCategory = item.id.isEmpty ? .general : item.id
                Button(item.name) {
                    applyCategory(categoryID)
                }
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Apply a category to \(selectedEntryIDs.count) selected entr\(selectedEntryIDs.count == 1 ? "y" : "ies").")
        }
        .alert("Delete selected entries?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                deleteSelectedEntries()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Delete \(selectedEntryIDs.count) selected entr\(selectedEntryIDs.count == 1 ? "y" : "ies") from the active library?")
        }
        .sheet(item: $shareItem) { item in
            ActivityView(items: [item.url])
        }
        .alert("Export failed", isPresented: Binding(
            get: { exportErrorMessage != nil },
            set: { if !$0 { exportErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {
                exportErrorMessage = nil
            }
        } message: {
            Text(exportErrorMessage ?? "Unable to export selected entries.")
        }
    }
    private var selectionStatusBar: some View {
        HStack(spacing: 12) {
            Text("\(selectedEntryIDs.count) selected")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.primary)

            Spacer()

            Button(showSelectedOnly ? "Show All" : "Show Selected") {
                showSelectedOnly.toggle()
            }
            .font(.footnote)
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.secondary.opacity(0.12))
        )
        .padding(.horizontal)
    }
    private var searchAndArrangeBar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField("Search entries", text: $query)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled(true)

                if !trimmedQuery.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.secondary.opacity(0.15))
            )

            HStack {
                Menu {
                    Button {
                        arrangeMode = .manual
                    } label: {
                        if arrangeMode == .manual {
                            Label("Manual", systemImage: "checkmark")
                        } else {
                            Text("Manual")
                        }
                    }

                    Button {
                        arrangeMode = .alphabeticalAZ
                    } label: {
                        if arrangeMode == .alphabeticalAZ {
                            Label("A–Z", systemImage: "checkmark")
                        } else {
                            Text("A–Z")
                        }
                    }

                    Button {
                        arrangeMode = .alphabeticalZA
                    } label: {
                        if arrangeMode == .alphabeticalZA {
                            Label("Z–A", systemImage: "checkmark")
                        } else {
                            Text("Z–A")
                        }
                    }

                    Button {
                        arrangeMode = .newestUpdated
                    } label: {
                        if arrangeMode == .newestUpdated {
                            Label("Newest", systemImage: "checkmark")
                        } else {
                            Text("Newest")
                        }
                    }

                    Button {
                        arrangeMode = .oldestUpdated
                    } label: {
                        if arrangeMode == .oldestUpdated {
                            Label("Oldest", systemImage: "checkmark")
                        } else {
                            Text("Oldest")
                        }
                    }

                    Button {
                        arrangeMode = .recentImports
                    } label: {
                        if arrangeMode == .recentImports {
                            Label("Recent Imports", systemImage: "checkmark")
                        } else {
                            Text("Recent Imports")
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text("Arrange")
                            .foregroundStyle(.secondary)
                        Text(arrangeDisplayName)
                            .lineLimit(1)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .font(.footnote)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.secondary.opacity(0.12))
                    )
                }
                .buttonStyle(.plain)

                Spacer()
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private var importedGroupsList: some View {
        List {
            ForEach(importedGroups) { group in
                Section {
                    ForEach(group.entries) { entry in
                        importedEntryRow(entry)
                    }
                } header: {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(importedBatchHeaderText(group.importedAt))
                                .font(.subheadline.weight(.semibold))
                            Text("\(group.entries.count) entr\(group.entries.count == 1 ? "y" : "ies")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if isSelecting {
                            Button(allEntriesSelected(in: group) ? "Deselect Batch" : "Select All") {
                                toggleBatchSelection(group)
                            }
                            .font(.caption)
                            .buttonStyle(.borderless)
                        }
                    }
                    .textCase(nil)
                }
            }
        }
    }

    private var flatEntriesList: some View {
        List {
            ForEach(flatEntries) { entry in
                importedEntryRow(entry)
            }
        }
    }

    @ViewBuilder
    private func importedEntryRow(_ entry: LibraryEntry) -> some View {
        HStack(spacing: 12) {
            if isSelecting {
                Image(systemName: selectedEntryIDs.contains(entry.id) ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selectedEntryIDs.contains(entry.id) ? Color.accentColor : Color.secondary)
                    .font(.system(size: 20, weight: .regular))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled Entry" : entry.title)
                    .font(.subheadline)
                    .foregroundStyle(.primary)

                HStack(spacing: 6) {
                    Text(categoryName(for: entry.category))
                    Text("•")
                    Text(importedRowTimestampText(entry.lastImportedAt))
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard isSelecting else { return }
            toggleSelection(for: entry.id)
        }
    }

    private func allEntriesSelected(in group: ImportedEntryGroup) -> Bool {
        !group.entries.isEmpty && group.entries.allSatisfy { selectedEntryIDs.contains($0.id) }
    }

    private func toggleBatchSelection(_ group: ImportedEntryGroup) {
        if allEntriesSelected(in: group) {
            for entry in group.entries {
                selectedEntryIDs.remove(entry.id)
            }
        } else {
            for entry in group.entries {
                selectedEntryIDs.insert(entry.id)
            }
        }
    }

    private func toggleSelection(for id: UUID) {
        if selectedEntryIDs.contains(id) {
            selectedEntryIDs.remove(id)
        } else {
            selectedEntryIDs.insert(id)
        }
    }

    private var selectedEntriesForExport: [LibraryEntry] {
        store.entries.filter { selectedEntryIDs.contains($0.id) }
    }

    private func exportSelectedEntries() {
        do {
            let data = try exportEntriesAsJSON(selectedEntriesForExport)
            let filename = sanitizedBatchExportFilename()

            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent(filename)
                .appendingPathExtension("json")

            try data.write(to: url, options: .atomic)
            shareItem = ShareItem(url: url)
        } catch {
            exportErrorMessage = error.localizedDescription
        }
    }

    private func exportEntriesAsJSON(_ entries: [LibraryEntry]) throws -> Data {
        let exportable = entries.map { entry in
            ExportableLibraryEntry(
                id: entry.id,
                title: entry.title.trimmingCharacters(in: .whitespacesAndNewlines),
                body: entry.attributedBody.string,
                category: entry.category,
                isFavorite: entry.isFavorite,
                isVisible: entry.isVisible,
                createdAt: entry.createdAt,
                updatedAt: entry.updatedAt
            )
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(exportable)
    }

    private func sanitizedBatchExportFilename() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return "SelectedEntries_\(formatter.string(from: Date()))"
    }

    private func deleteSelectedEntries() {
        store.deleteEntries(withIDs: selectedEntryIDs)
        selectedEntryIDs.removeAll()
        isSelecting = false
        showSelectedOnly = false
    }

    private func applyCategory(_ category: EntryCategory) {
        store.updateEntryCategories(ids: selectedEntryIDs, to: category)
        selectedEntryIDs.removeAll()
        isSelecting = false
        showSelectedOnly = false
    }

    private func categoryName(for category: EntryCategory) -> String {
        store.sortedCategories().first(where: { ($0.id.isEmpty ? EntryCategory.general : $0.id) == category })?.name ?? "General"
    }

    private func importedBatchHeaderText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM yyyy, h:mm:ss a"
        return formatter.string(from: date)
    }

    private func importedRowTimestampText(_ date: Date?) -> String {
        guard let date else { return "No import timestamp" }
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM yyyy, h:mm:ss a"
        return formatter.string(from: date)
    }
}
private struct ManageEntryDetail: View {
    @EnvironmentObject private var store: AppStore
    @Binding var selectedID: UUID?
    @Binding var isEditingExternal: Bool
    @Binding var hasUnsavedChangesExternal: Bool
    @Binding var autoStartEditingEntryID: UUID?
    @Binding var draftNewEntryID: UUID?
    @State private var showDeleteConfirm: Bool = false

    let entry: LibraryEntry

    @State private var title: String = ""
    @State private var bodyAttributed: NSAttributedString = NSAttributedString(string: "")
    @State private var category: EntryCategory = .general
    @State private var isFavorite: Bool = false
    @State private var isVisible: Bool = true

    @State private var didLoad = false

    @State private var isEditing: Bool = false

    @State private var originalTitle: String = ""
    @State private var originalBodyAttributed: NSAttributedString = NSAttributedString(string: "")
    @State private var originalCategory: EntryCategory = .general
    @State private var originalIsFavorite: Bool = false
    @State private var originalIsVisible: Bool = true
    @State private var shareItem: ShareItem? = nil
    @State private var exportErrorMessage: String? = nil
    
    @StateObject private var richTextCommands = RichTextEditorCommands()

    private var bodyFieldLabel: String {
        "Entry Content"
    }

    private var hasUnsavedChanges: Bool {
        let currentRTF = (try? bodyAttributed.eyeBrary_toRTFData()) ?? Data()
        let originalRTF = (try? originalBodyAttributed.eyeBrary_toRTFData()) ?? Data()

        return title != originalTitle
            || currentRTF != originalRTF
    }

    private var canSaveEntry: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var isDraftNewEntry: Bool {
        draftNewEntryID == entry.id
    }

    private var metadataWordCount: Int {
        bodyAttributed.string
            .split { $0.isWhitespace || $0.isNewline }
            .count
    }

    private var metadataReadText: String {
        let seconds = max(10, Int(Double(metadataWordCount) / 3.5))
        return seconds < 60
            ? "~\(seconds) sec read"
            : "~\(seconds / 60) min read"
    }

    private var metadataLastModifiedText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd MMM yyyy"
        return formatter.string(from: entry.updatedAt).uppercased()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                TextField("Entry title", text: $title)
                    .textFieldStyle(.roundedBorder)
                    .font(.title3)
                    .disabled(!isEditing)

                Spacer()

                ZStack(alignment: .topTrailing) {
                    Group {
                        if isEditing {
                            HStack(spacing: 8) {
                                Button(hasUnsavedChanges ? "Save" : "Done") {
                                    commitEdits()
                                    isEditing = false
                                    isEditingExternal = false
                                    hasUnsavedChangesExternal = false
                                }
                                .buttonStyle(.bordered)
                                .disabled(!canSaveEntry)

                                Button("Cancel") {
                                    if isDraftNewEntry {
                                        store.entries.removeAll { $0.id == entry.id }
                                        if selectedID == entry.id {
                                            selectedID = nil
                                        }
                                        draftNewEntryID = nil
                                        autoStartEditingEntryID = nil
                                        isEditing = false
                                        isEditingExternal = false
                                        hasUnsavedChangesExternal = false
                                    } else {
                                        discardEdits()
                                        isEditing = false
                                        isEditingExternal = false
                                        hasUnsavedChangesExternal = false
                                    }
                                }
                                .buttonStyle(.bordered)
                            }
                        } else {
                            Button("Edit") {
                                beginEditing()
                                isEditing = true
                                isEditingExternal = true
                                hasUnsavedChangesExternal = false
                            }
                            .buttonStyle(.bordered)
                        }
                    }

                    Button {
                        exportCurrentEntry()
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                    .offset(x: -17, y: -50)
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)

            HStack(alignment: .center, spacing: 20) {
                HStack(spacing: 12) {
                    Text("Category")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Picker("Category", selection: $category) {
                        let cats = store.categories.sorted { $0.order < $1.order }
                        ForEach(cats) { item in
                            Text(item.name).tag(item.id.isEmpty ? .general : item.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(minWidth: 180, alignment: .leading)
                }

                HStack(spacing: 12) {
                    Text("Visible in New Report")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Button {
                        isVisible.toggle()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: isVisible ? "largecircle.fill.circle" : "circle")
                                .font(.system(size: 18))
                                .foregroundStyle(isVisible ? Color.accentColor : Color.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .padding(.leading, 100)

                Spacer()

                Button {
                    isFavorite.toggle()
                } label: {
                    HStack(spacing: 8) {
                        Text("Favorite")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Image(systemName: isFavorite ? "star.fill" : "star")
                            .foregroundStyle(isFavorite ? Color.yellow : Color.secondary)
                            .font(.system(size: 22, weight: .semibold))
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(bodyFieldLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    if isEditing {
                        HStack(spacing: 8) {
                            Button {
                                richTextCommands.toggleBold()
                            } label: {
                                Image(systemName: "bold")
                            }
                            .buttonStyle(.bordered)

                            Button {
                                richTextCommands.toggleUnderline()
                            } label: {
                                Image(systemName: "underline")
                            }
                            .buttonStyle(.bordered)

                            Button {
                                richTextCommands.indent()
                            } label: {
                                Image(systemName: "increase.indent")
                            }
                            .buttonStyle(.bordered)

                            Button {
                                richTextCommands.outdent()
                            } label: {
                                Image(systemName: "decrease.indent")
                            }
                            .buttonStyle(.bordered)

                            Button {
                                richTextCommands.toggleBullets()
                            } label: {
                                Image(systemName: "list.bullet")
                            }
                            .buttonStyle(.bordered)

                            Button {
                                richTextCommands.toggleNumberedList()
                            } label: {
                                Image(systemName: "list.number")
                            }
                            .buttonStyle(.bordered)

                            Button {
                                richTextCommands.normalizeFormatting()
                            } label: {
                                Image(systemName: "wand.and.stars")
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }

                RichTextEditor(
                    attributedText: $bodyAttributed,
                    isEditable: isEditing,
                    font: .preferredFont(forTextStyle: .title3),
                    commands: richTextCommands
                )
                    .frame(minHeight: 260)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isEditing && hasUnsavedChanges ? Color.red : .secondary.opacity(0.35))
                    )
            }
            .padding(.horizontal)


            if isEditing {
                HStack(alignment: .center) {
                    Text("\(metadataWordCount) words (\(metadataReadText))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text("last modified: \(metadataLastModifiedText)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Label("Delete Entry", systemImage: "trash")
                            .font(.subheadline)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal)
            }
            
            Spacer()
        }
        .alert("Delete entry?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                let id = entry.id
                store.deleteEntries(withIDs: [id])
                selectedID = nil
                isEditing = false
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete the library entry.")
        }
        .sheet(item: $shareItem) { item in
            ActivityView(items: [item.url])
        }
        .alert("Export failed", isPresented: Binding(
            get: { exportErrorMessage != nil },
            set: { if !$0 { exportErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {
                exportErrorMessage = nil
            }
        } message: {
            Text(exportErrorMessage ?? "Unable to export this entry.")
        }
        .onAppear {
            loadIfNeeded()
            isEditing = false
            isEditingExternal = false
            hasUnsavedChangesExternal = false
            startEditingIfRequested()
        }
        .onChange(of: entry.id) { _, _ in
            didLoad = false
            isEditing = false
            isEditingExternal = false
            hasUnsavedChangesExternal = false
            loadIfNeeded()
            startEditingIfRequested()
        }
        .onChange(of: isEditing) { _, newValue in
            isEditingExternal = newValue
            if !newValue {
                hasUnsavedChangesExternal = false
            } else {
                hasUnsavedChangesExternal = hasUnsavedChanges
            }
        }
        .onChange(of: title) { _, _ in
            if isEditing {
                hasUnsavedChangesExternal = hasUnsavedChanges
            }
        }
        .onChange(of: bodyAttributed) { _, _ in
            if isEditing {
                hasUnsavedChangesExternal = hasUnsavedChanges
            }
        }
        .onChange(of: category) { _, _ in
            saveMetadataChangesIfNeeded()
        }
        .onChange(of: isFavorite) { _, _ in
            saveMetadataChangesIfNeeded()
        }
        .onChange(of: isVisible) { _, _ in
            saveMetadataChangesIfNeeded()
        }
    }
    private func exportCurrentEntry() {
        do {
            let data = try exportEntryAsJSON(exportSnapshot)
            let filename = sanitizedExportFilename(from: exportSnapshot.title)

            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent(filename)
                .appendingPathExtension("json")

            try data.write(to: url, options: .atomic)
            shareItem = ShareItem(url: url)
        } catch {
            exportErrorMessage = error.localizedDescription
        }
    }
    private var exportSnapshot: LibraryEntry {
        var snapshot = entry
        snapshot.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        snapshot.setAttributedBody(bodyAttributed)
        snapshot.category = category
        snapshot.isFavorite = isFavorite
        snapshot.isVisible = isVisible
        return snapshot
    }

    private func sanitizedExportFilename(from title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)

        let cleaned = trimmed.replacingOccurrences(
            of: #"[^A-Za-z0-9 _-]"#,
            with: "",
            options: .regularExpression
        )

        let collapsedWhitespace = cleaned.replacingOccurrences(
            of: #"\s+"#,
            with: " ",
            options: .regularExpression
        )

        let final = collapsedWhitespace
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "_")

        return final.isEmpty ? "LibraryEntry" : final
    }

    private func startEditingIfRequested() {
        guard autoStartEditingEntryID == entry.id else { return }
        beginEditing()
        isEditing = true
        isEditingExternal = true
        hasUnsavedChangesExternal = hasUnsavedChanges
        autoStartEditingEntryID = nil
    }

    private func saveMetadataChangesIfNeeded() {
        guard didLoad else { return }
        guard !isEditing else { return }
        guard var t = store.entry(id: entry.id) else { return }

        let metadataChanged = t.category != category
            || t.isFavorite != isFavorite
            || t.isVisible != isVisible

        guard metadataChanged else { return }

        t.category = category
        t.isFavorite = isFavorite
        t.isVisible = isVisible
        t.updatedAt = Date()
        store.updateEntry(t)

        originalCategory = t.category
        originalIsFavorite = t.isFavorite
        originalIsVisible = t.isVisible
    }
    private func loadIfNeeded() {
        guard !didLoad else { return }
        didLoad = true

        title = entry.title
        bodyAttributed = entry.attributedBody
        category = entry.category
        originalCategory = entry.category
        isFavorite = entry.isFavorite
        isVisible = entry.isVisible
        originalIsFavorite = entry.isFavorite
        originalIsVisible = entry.isVisible

        // Capture originals so Cancel can revert.
        originalTitle = entry.title
        originalBodyAttributed = entry.attributedBody
    }

    private func beginEditing() {
        // Refresh originals from the current stored version.
        guard let t = store.entry(id: entry.id) else { return }
        originalTitle = t.title
        originalBodyAttributed = t.attributedBody
        originalCategory = t.category
        originalIsFavorite = t.isFavorite
        originalIsVisible = t.isVisible

        title = t.title
        bodyAttributed = t.attributedBody
        category = t.category
        isFavorite = t.isFavorite
        isVisible = t.isVisible
    }

    private func discardEdits() {
        title = originalTitle
        bodyAttributed = originalBodyAttributed
        category = originalCategory
        isFavorite = originalIsFavorite
        isVisible = originalIsVisible
        isEditingExternal = false
        hasUnsavedChangesExternal = false
    }

    private func commitEdits() {
        guard didLoad else { return }
        guard canSaveEntry else { return }
        guard var t = store.entry(id: entry.id) else { return }

        t.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        t.setAttributedBody(bodyAttributed)
        t.category = category
        t.isFavorite = isFavorite
        t.isVisible = isVisible

        t.updatedAt = Date()
        store.updateEntry(t)

        // Update originals after saving.
        originalTitle = t.title
        originalBodyAttributed = t.attributedBody
        originalCategory = t.category
        originalIsFavorite = t.isFavorite
        originalIsVisible = t.isVisible
        if draftNewEntryID == t.id {
            draftNewEntryID = nil
        }
        isEditingExternal = false
        hasUnsavedChangesExternal = false
    }
}

