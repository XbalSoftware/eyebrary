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

    private var filtered: [LibraryEntry] {
        let base = store.entries.filter { matchesCategory($0, filter: categoryFilter) }
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)

        let list: [LibraryEntry]
        if q.isEmpty {
            list = base.sorted { a, b in
                let ao = a.order ?? Int.max
                let bo = b.order ?? Int.max
                if ao != bo { return ao < bo }
                return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
            }
        } else {
            list = base.filter {
                $0.title.localizedCaseInsensitiveContains(q) ||
                $0.body.localizedCaseInsensitiveContains(q)
            }
            .sorted { a, b in
                let aTitleMatch = a.title.localizedCaseInsensitiveContains(q)
                let bTitleMatch = b.title.localizedCaseInsensitiveContains(q)

                if aTitleMatch != bTitleMatch {
                    return aTitleMatch && !bTitleMatch
                }

                let ao = a.order ?? Int.max
                let bo = b.order ?? Int.max
                if ao != bo { return ao < bo }
                return a.updatedAt > b.updatedAt
            }
        }
        return list
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
        .alert("Delete entry?", isPresented: $showDeleteEntryConfirm) {
            Button("Delete", role: .destructive) {
                if let id = pendingDeleteEntryID,
                   let idx = store.entries.firstIndex(where: { $0.id == id }) {
                    store.entries.remove(at: idx)
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

            Spacer()

            Text("Library")
                .font(.system(size: 20, weight: .bold))

            Spacer()

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
        }
        .padding(.horizontal)
        .padding(.top, 8)
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
                    Text("Category:")
                        .foregroundStyle(.secondary)
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
        // Only allow reordering when not searching.
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.isEmpty else { return }

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
        for id in ids {
            guard var t = store.entry(id: id) else { continue }
            t.category = newCategory
            t.updatedAt = Date()
            store.updateEntry(t)
        }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                TextField("Entry title", text: $title)
                    .textFieldStyle(.roundedBorder)
                    .font(.title3)
                    .disabled(!isEditing)

                Spacer()

                if isEditing {
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
            .padding(.horizontal)
            .padding(.top, 8)

            HStack {
                Text("Category")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("Category", selection: $category) {
                    let cats = store.categories.sorted { $0.order < $1.order }
                    ForEach(cats) { item in
                        Text(item.name).tag(item.id.isEmpty ? .general : item.id)
                    }
                }
                .pickerStyle(.menu)
            }
            .padding(.horizontal)

            HStack {
                Text("Visible in New Report")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer()

                Toggle("", isOn: $isVisible)
                    .labelsHidden()
            }
            .padding(.horizontal)

            HStack {
                Text("Favorite")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer()

                Toggle("", isOn: $isFavorite)
                    .labelsHidden()
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
                HStack {
                    Spacer()

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
                store.entries.removeAll { $0.id == id }
                selectedID = nil
                isEditing = false
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete the library entry.")
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

