//
//  NewReportView.swift
//  EYEbrary
//
//  Created by Simon Reid on 2026-03-15.
//

// MARK: - New Report

import SwiftUI
import Foundation
import UIKit

struct NewReportView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.scenePhase) private var scenePhase

    private struct DraftPayload: Codable {
        var reportTitle: String
        var reportDate: Date
        var entries: [PlanEntry]
    }

    @State private var selectedEntryID: UUID? = nil
    @State private var categoryFilter: CategoryFilter = .all
    @State private var favoritesOnly: Bool = false

    // Sidebar search (New Report)
    @State private var query: String = ""
    // BRIDGE_TEST: ok

    @State private var reportTitle: String = ""

    private let reportTitlePresets: [String] = [
        "Eye Exam Summary",
        "Patient Information",
        "Topics Discussed",
        "Instructions"
    ]
    @State private var patientName: String = ""
    @State private var reportDate: Date = Date()
    @State private var planEntries: [PlanEntry] = []

    private var currentSortMode: LibrarySortMode {
        store.sortMode()
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

    @State private var shareItem: ShareItem? = nil
    @State private var pendingDeleteEntryID: UUID? = nil
    @State private var showDeleteWarning: Bool = false
    @State private var showHistorySheet: Bool = false
    @State private var collapsedSelectedEntries: Bool = false
    @State private var expandedEntryIDs: Set<UUID> = []
    @State private var richTextCommandsByEntryID: [UUID: RichTextEditorCommands] = [:]
    @State private var pendingScrollEntryID: UUID? = nil
    @State private var showDraftRestoredBanner: Bool = false

    private let draftStorageKey = "EYEbrary.currentDraft.v1"

    private var filteredEntries: [LibraryEntry] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = store.entries
            .filter { $0.isVisible && matchesCategory($0, filter: categoryFilter) }
            .filter { !favoritesOnly || $0.isFavorite }

        let filtered = q.isEmpty ? base : base.filter {
            $0.title.localizedCaseInsensitiveContains(q) ||
            $0.body.localizedCaseInsensitiveContains(q)
        }

        return filtered.sorted { a, b in
            if !q.isEmpty {
                let aTitleMatch = a.title.localizedCaseInsensitiveContains(q)
                let bTitleMatch = b.title.localizedCaseInsensitiveContains(q)

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
    private var orderedCategories: [CategoryItem] {
        store.categories.sorted { $0.order < $1.order }
    }

    private var nonGeneralCategories: [CategoryItem] {
        orderedCategories.filter { ($0.id.isEmpty ? EntryCategory.general : $0.id) != .general }
    }
    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .navigationTitle("EYEbrary")
        .onChange(of: store.activeLibraryID) { _, _ in
            selectedEntryID = nil
        }
        .sheet(item: $shareItem) { item in
            ActivityView(items: [item.url])
        }
        .sheet(isPresented: $showHistorySheet) {
            HistorySheet(
                history: store.history,
                onRestore: { saved in
                    stashCurrentReportInHistoryBeforeRestore()
                    reportTitle = saved.reportTitle
                    reportDate = saved.reportDate
                    patientName = saved.patientName
                    planEntries = saved.entries
                    selectedEntryID = nil
                    showHistorySheet = false
                },
                onDelete: { offsets in
                    store.deleteHistory(at: offsets)
                },
                onClearAll: {
                    store.clearHistory()
                }
            )
        }
        .alert("Discard changes?", isPresented: $showDeleteWarning) {
            Button("Delete", role: .destructive) {
                if let id = pendingDeleteEntryID {
                    deleteEntryNow(id: id)
                }
                pendingDeleteEntryID = nil
            }
            Button("Cancel", role: .cancel) {
                pendingDeleteEntryID = nil
            }
        } message: {
            Text("This item has edits. Deleting it will lose your changes.")
        }
        .overlay(alignment: .top) {
            if showDraftRestoredBanner {
                Text("Draft Restored (patient name not saved for privacy)")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        Capsule()
                            .fill(Color.secondary.opacity(0.16))
                    )
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .onAppear {
            restoreDraftIfAvailable()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .inactive || newPhase == .background {
                persistCurrentDraft()
            }
        }
    }

    private var sidebar: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Button {
                    favoritesOnly.toggle()
                } label: {
                    Image(systemName: favoritesOnly ? "star.fill" : "star")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(favoritesOnly ? Color.yellow : Color.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(favoritesOnly ? "Showing favorites" : "Show favorites")
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
                    addOtherEntry()
                } label: {
                    Label("Add Other", systemImage: "plus")
                        .labelStyle(.iconOnly)
                        .font(.system(size: 18, weight: .semibold))
                }
                .buttonStyle(.plain)
                .frame(width: 24, alignment: .center)
                .padding(.trailing, 6)
            }
            .padding(.top, 8)

            if favoritesOnly {
                Text("Showing Favorites")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal)
            }

            // Category selector
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
                            Label("Newest", systemImage: "checkmark")
                        } else {
                            Text("Newest")
                        }
                    }

                    Button {
                        store.setSortMode(.oldestUpdated)
                    } label: {
                        if currentSortMode == .oldestUpdated {
                            Label("Oldest", systemImage: "checkmark")
                        } else {
                            Text("Oldest")
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
            }
            .padding(.horizontal)

            // Search (placed under Basic/Advanced)
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

           List(selection: $selectedEntryID) {
                Section {
                    if filteredEntries.isEmpty {
                        if favoritesOnly {
                            ContentUnavailableView(
                                "No favorites yet",
                                systemImage: "star",
                                description: Text("Mark entries as favorites in the Library to access them quickly here.")
                            )
                        } else {
                            ContentUnavailableView(
                                "No entries found",
                                systemImage: "doc.text",
                                description: Text("Try a different search or category filter.")
                            )
                        }
                    } else {
                        ForEach(filteredEntries) { t in
                            Button {
                                toggleEntrySelection(t)
                            } label: {
                                HStack(spacing: 10) {
                                    Text(t.title)
                                        .font(.subheadline)
                                        .multilineTextAlignment(.leading)
                                        .layoutPriority(1)

                                    Spacer()

                                    if isEntrySelected(t.id) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(Color.accentColor)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    private var detail: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Spacer()

                Button {
                    showHistorySheet = true
                } label: {
                    Label("History", systemImage: "clock.arrow.circlepath")
                }
                .buttonStyle(.bordered)

                Button("Clear") {
                    clearForm()
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal)
            .padding(.top, 6)

            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    TextField("Report Title (optional)", text: $reportTitle)
                        .textFieldStyle(.roundedBorder)

                    Menu {
                        Button("(No title)") {
                            reportTitle = ""
                        }
                        Divider()
                        ForEach(reportTitlePresets, id: \.self) { preset in
                            Button {
                                reportTitle = preset
                            } label: {
                                if reportTitle.trimmingCharacters(in: .whitespacesAndNewlines) == preset {
                                    Label(preset, systemImage: "checkmark")
                                } else {
                                    Text(preset)
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .listRowSeparatorTint(Color.accentColor.opacity(0.7))
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.secondary.opacity(0.12))
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Choose a report title")
                }

                HStack(spacing: 12) {
                    TextField("Patient Name (optional)", text: $patientName)
                        .textFieldStyle(.roundedBorder)

                    DatePicker(
                        "Date",
                        selection: $reportDate,
                        displayedComponents: [.date]
                    )
                    .datePickerStyle(.compact)
                    .labelsHidden()
                }
            }
            .padding(.horizontal)
            .padding(.top, -10)

            if planEntries.isEmpty {
                ContentUnavailableView(
                    "No entries selected",
                    systemImage: "doc.text",
                    description: Text("Select library entries from the left panel to build the report.")
                )
                .padding(.top, 20)
            } else {
                HStack {
                    Text("Selected")
                        .font(.headline)

                    Spacer()

                    Button(collapsedSelectedEntries ? "Expand" : "Collapse") {
                        collapsedSelectedEntries.toggle()
                        if collapsedSelectedEntries {
                            expandedEntryIDs.removeAll()
                        }
                    }
                    .font(.subheadline)
                    .buttonStyle(.plain)
                }
                .padding(.horizontal)
                .padding(.top, -2)

                ScrollViewReader { proxy in
                    List {
                        Section {
                            ForEach($planEntries) { $entry in
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack(alignment: .top) {
                                        TextField("ENTER TITLE", text: $entry.title)
                                            .textFieldStyle(.plain)
                                            .font(.headline)
                                            .textInputAutocapitalization(.characters)
                                            .autocorrectionDisabled(true)

                                        Spacer()
                                        Button {
                                            requestDelete(entryID: entry.id)
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundStyle(.secondary)
                                        }
                                        .buttonStyle(.plain)
                                    }

                                    if !collapsedSelectedEntries {
                                        VStack(alignment: .leading, spacing: 6) {
                                            HStack {
                                                Button {
                                                    if expandedEntryIDs.contains(entry.id) {
                                                        expandedEntryIDs.remove(entry.id)
                                                    } else {
                                                        expandedEntryIDs.insert(entry.id)
                                                        DispatchQueue.main.async {
                                                            withAnimation(.easeInOut(duration: 0.2)) {
                                                                proxy.scrollTo(entry.id, anchor: .top)
                                                            }
                                                        }
                                                    }
                                                } label: {
                                                    Text("Expand Content")
                                                        .font(.caption)
                                                        .foregroundStyle(expandedEntryIDs.contains(entry.id) ? Color.accentColor : Color.secondary)
                                                }
                                                .buttonStyle(.plain)

                                                Spacer()

                                                HStack(spacing: 8) {
                                                    Button {
                                                        richTextCommands(for: entry.id).toggleBold()
                                                    } label: {
                                                        Image(systemName: "bold")
                                                    }
                                                    .buttonStyle(.bordered)

                                                    Button {
                                                        richTextCommands(for: entry.id).toggleUnderline()
                                                    } label: {
                                                        Image(systemName: "underline")
                                                    }
                                                    .buttonStyle(.bordered)

                                                    Button {
                                                        richTextCommands(for: entry.id).indent()
                                                    } label: {
                                                        Image(systemName: "increase.indent")
                                                    }
                                                    .buttonStyle(.bordered)

                                                    Button {
                                                        richTextCommands(for: entry.id).outdent()
                                                    } label: {
                                                        Image(systemName: "decrease.indent")
                                                    }
                                                    .buttonStyle(.bordered)

                                                    Button {
                                                        richTextCommands(for: entry.id).toggleBullets()
                                                    } label: {
                                                        Image(systemName: "list.bullet")
                                                    }
                                                    .buttonStyle(.bordered)

                                                    Button {
                                                        richTextCommands(for: entry.id).toggleNumberedList()
                                                    } label: {
                                                        Image(systemName: "list.number")
                                                    }
                                                    .buttonStyle(.bordered)

                                                    Button {
                                                        richTextCommands(for: entry.id).normalizeFormatting()
                                                    } label: {
                                                        Image(systemName: "wand.and.stars")
                                                    }
                                                    .buttonStyle(.bordered)
                                                }
                                            }

                                            RichTextEditor(
                                                attributedText: Binding(
                                                    get: { entry.attributedBody },
                                                    set: { newValue in
                                                        entry.setAttributedBody(newValue)
                                                    }
                                                ),
                                                isEditable: true,
                                                font: .preferredFont(forTextStyle: .title3),
                                                commands: richTextCommands(for: entry.id)
                                            )
                                            .frame(minHeight: expandedEntryIDs.contains(entry.id) ? 420 : 180)
                                            .contentShape(Rectangle())
                                            .background(
                                                RoundedRectangle(cornerRadius: 8)
                                                    .fill(Color.black.opacity(0.35))
                                            )
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 8)
                                                    .stroke(
                                                        expandedEntryIDs.contains(entry.id)
                                                            ? Color.accentColor
                                                            : Color.secondary.opacity(0.35),
                                                        lineWidth: expandedEntryIDs.contains(entry.id) ? 1.5 : 1
                                                    )
                                            )
                                        }
                                    }
                                }
                                .padding(.vertical, 8)
                                .id(entry.id)
                            }
                            .onMove { from, to in
                                planEntries.move(fromOffsets: from, toOffset: to)
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            }
                        }
                    }
                    .environment(\.editMode, .constant(.active))
                    .onChange(of: pendingScrollEntryID) { _, newValue in
                        guard let entryID = newValue else { return }
                        DispatchQueue.main.async {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                proxy.scrollTo(entryID, anchor: .top)
                            }
                            pendingScrollEntryID = nil
                        }
                    }
                }
            }

            HStack(spacing: 12) {
                Button {
                    generateAndSharePDF()
                } label: {
                    Label("Export PDF", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.borderedProminent)
                .disabled(planEntries.isEmpty)

                Menu {
                    Button("Blank (Built-in)") {
                        store.selectedLetterheadName = nil
                    }

                    if !store.letterheads.isEmpty {
                        Divider()

                        ForEach(store.letterheads, id: \.self) { name in
                            Button {
                                store.selectedLetterheadName = name
                            } label: {
                                if store.selectedLetterheadName == name {
                                    Label(name, systemImage: "checkmark")
                                } else {
                                    Text(name)
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "doc.text")
                            .font(.body)
                        Text(store.selectedLetterheadName ?? "Blank (Built-in)")
                            .font(.body)
                            .lineLimit(1)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.secondary.opacity(0.12))
                    )
                }
                .buttonStyle(.plain)

                Spacer()
            }
            .padding([.horizontal, .bottom])
        }
        .padding(.top, -56)
    }
    private func richTextCommands(for entryID: UUID) -> RichTextEditorCommands {
        if let existing = richTextCommandsByEntryID[entryID] {
            return existing
        }
        return RichTextEditorCommands()
    }

    private func addToPlan(templateID: UUID) {
        guard let t = store.entry(id: templateID) else { return }
        if planEntries.contains(where: { $0.templateID == templateID }) { return }

        let newID = UUID()
        planEntries.append(
            PlanEntry(
                id: newID,
                templateID: templateID,
                title: t.title,
                originalTitle: t.title,
                body: t.body,
                originalBody: t.body,
                bodyRTFData: t.bodyRTFData,
                originalBodyRTFData: t.bodyRTFData
            )
        )
        richTextCommandsByEntryID[newID] = RichTextEditorCommands()
        pendingScrollEntryID = newID
    }
    private func isEntrySelected(_ entryID: UUID) -> Bool {
        planEntries.contains(where: { $0.templateID == entryID })
    }

    private func toggleEntrySelection(_ entry: LibraryEntry) {
        if let selectedPlanEntry = planEntries.first(where: { $0.templateID == entry.id }) {
            requestDelete(entryID: selectedPlanEntry.id)
            selectedEntryID = nil
        } else {
            addToPlan(templateID: entry.id)
            selectedEntryID = entry.id
        }
    }
    private func addOtherEntry() {
        let newID = UUID()
        planEntries.insert(
            PlanEntry(
                id: newID,
                templateID: nil,
                title: "",
                originalTitle: "",
                body: "",
                originalBody: "",
                bodyRTFData: nil,
                originalBodyRTFData: nil
            ),
            at: 0
        )
        richTextCommandsByEntryID[newID] = RichTextEditorCommands()
        pendingScrollEntryID = newID
    }
    private func needsDeleteWarning(for entry: PlanEntry) -> Bool {
        if entry.templateID == nil {
            let trimmedTitle = entry.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedBody = entry.body.trimmingCharacters(in: .whitespacesAndNewlines)

            let hasEdits = !trimmedBody.isEmpty || !trimmedTitle.isEmpty
            return hasEdits
        }
        return entry.body != entry.originalBody
            || entry.title != entry.originalTitle
            || entry.bodyRTFData != entry.originalBodyRTFData
    }

    private func requestDelete(entryID: UUID) {
        guard let entry = planEntries.first(where: { $0.id == entryID }) else { return }
        if needsDeleteWarning(for: entry) {
            pendingDeleteEntryID = entryID
            showDeleteWarning = true
        } else {
            deleteEntryNow(id: entryID)
        }
    }

    private func deleteEntryNow(id: UUID) {
        planEntries.removeAll { $0.id == id }
        expandedEntryIDs.remove(id)
        richTextCommandsByEntryID.removeValue(forKey: id)
    }
    
    private func persistCurrentDraft() {
        let trimmedPatientName = patientName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedReportTitle = reportTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasMeaningfulCurrentWork = !planEntries.isEmpty || !trimmedReportTitle.isEmpty || !trimmedPatientName.isEmpty

        guard hasMeaningfulCurrentWork else {
            UserDefaults.standard.removeObject(forKey: draftStorageKey)
            return
        }

        let payload = DraftPayload(
            reportTitle: reportTitle,
            reportDate: reportDate,
            entries: planEntries
        )

        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(payload)
            UserDefaults.standard.set(data, forKey: draftStorageKey)
        } catch {
            print("Draft save failed:", error)
        }
    }

    private func restoreDraftIfAvailable() {
        guard let data = UserDefaults.standard.data(forKey: draftStorageKey) else { return }

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let payload = try decoder.decode(DraftPayload.self, from: data)

            reportTitle = payload.reportTitle
            reportDate = payload.reportDate
            patientName = ""
            planEntries = payload.entries
            selectedEntryID = nil
            expandedEntryIDs.removeAll()
            richTextCommandsByEntryID = Dictionary(uniqueKeysWithValues: payload.entries.map { ($0.id, RichTextEditorCommands()) })

            withAnimation(.easeInOut(duration: 0.2)) {
                showDraftRestoredBanner = true
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showDraftRestoredBanner = false
                }
            }
        } catch {
            print("Draft restore failed:", error)
            UserDefaults.standard.removeObject(forKey: draftStorageKey)
        }
    }

    private func stashCurrentReportInHistoryBeforeRestore() {
        let trimmedPatientName = patientName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedReportTitle = reportTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasMeaningfulCurrentWork = !planEntries.isEmpty || !trimmedPatientName.isEmpty || !trimmedReportTitle.isEmpty
        guard hasMeaningfulCurrentWork else { return }

        store.addToHistory(
            reportTitle: reportTitle,
            reportDate: reportDate,
            patientName: "",
            entries: planEntries
        )
    }
    private func clearForm() {
        // Privacy: do not store patient name in history.
        store.addToHistory(reportTitle: reportTitle, reportDate: reportDate, patientName: "", entries: planEntries)
        UserDefaults.standard.removeObject(forKey: draftStorageKey)
        // Clear form fields.
        reportTitle = ""
        patientName = ""
        reportDate = Date()
        planEntries = []
        expandedEntryIDs.removeAll()
        richTextCommandsByEntryID.removeAll()
        selectedEntryID = nil
    }

    private func generateAndSharePDF() {
        do {
            let url = try PlanPDFBuilder.buildPDF(
                patientName: patientName,
                reportTitle: reportTitle,
                reportDate: reportDate,
                entries: planEntries,
                letterheadURL: store.selectedLetterheadName.map { store.letterheadURL(named: $0) } ?? store.bundledBlankLetterheadURL(),
                safeZoneConfig: store.selectedLetterheadName.flatMap { store.safeZoneConfig(named: $0) }
            )
            shareItem = ShareItem(url: url)
        } catch {
            print("PDF export failed:", error)
        }
    }
}
