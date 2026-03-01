//
//  ContentView.swift
//  Summary
//
//  Created by Simon Reid on 2026-03-01.
//

import SwiftUI
import Combine
import UIKit
import UniformTypeIdentifiers
import PDFKit

// MARK: - Data Model

enum TemplateLevel: String, Codable, CaseIterable, Identifiable {
    case basic
    case advanced

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .basic: return "Basic"
        case .advanced: return "Advanced"
        }
    }
}

struct ConditionTemplate: Identifiable, Codable, Equatable {
    var id: UUID = UUID()

    var title: String
    var assessment: String
    var plan: String

    var level: TemplateLevel
    var isPinned: Bool

    var createdAt: Date = Date()
    var updatedAt: Date = Date()
}

struct PlanEntry: Identifiable, Codable, Equatable {
    var id: UUID
    var templateID: UUID?   // nil for “Other”
    var title: String
    var assessment: String
    var plan: String
    var originalAssessment: String
    var originalPlan: String
}

struct SavedPlan: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var savedAt: Date = Date()
    var level: TemplateLevel
    var patientName: String
    var entries: [PlanEntry]
}

private struct LetterheadState: Codable {
    var letterheads: [String]
    var selected: String?
}

// MARK: - JSON helpers

extension JSONEncoder {
    static let standard: JSONEncoder = {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        return enc
    }()

    static let pretty: JSONEncoder = {
        let enc = JSONEncoder.standard
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return enc
    }()
}

extension JSONDecoder {
    static let standard: JSONDecoder = {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return dec
    }()
}

// MARK: - Store

@MainActor
final class AppStore: ObservableObject {
    // Templates
    @Published var templates: [ConditionTemplate] = [] {
        didSet { persistTemplates() }
    }

    // Letterheads
    @Published var letterheads: [String] = [] {
        didSet { persistLetterheads() }
    }
    @Published var selectedLetterheadName: String? {
        didSet { persistLetterheads() }
    }

    // History (last 5 plans)
    @Published var history: [SavedPlan] = [] {
        didSet { persistHistory() }
    }

    private let templatesKey = "summary.conditionTemplates.v1"
    private let letterheadsKey = "summary.letterheads.v1"
    private let historyKey = "summary.history.v1"

    init() {
        loadTemplates()
        loadLetterheads()
        loadHistory()
        if templates.isEmpty { seedDefaults() }
    }

    // MARK: Templates

    func addTemplate(_ t: ConditionTemplate) {
        templates.insert(t, at: 0)
    }

    func updateTemplate(_ t: ConditionTemplate) {
        guard let idx = templates.firstIndex(where: { $0.id == t.id }) else { return }
        templates[idx] = t
    }

    func deleteTemplates(at offsets: IndexSet, in filtered: [ConditionTemplate]) {
        let idsToDelete = offsets.map { filtered[$0].id }
        templates.removeAll { idsToDelete.contains($0.id) }
    }

    func togglePinned(id: UUID) {
        guard let idx = templates.firstIndex(where: { $0.id == id }) else { return }
        templates[idx].isPinned.toggle()
        templates[idx].updatedAt = Date()
    }

    func template(id: UUID) -> ConditionTemplate? {
        templates.first(where: { $0.id == id })
    }

    // MARK: Import/Export Templates

    func exportTemplatesJSON() throws -> Data {
        try JSONEncoder.pretty.encode(templates)
    }

    func importTemplatesJSON(_ data: Data, merge: Bool) throws {
        let incoming = try JSONDecoder.standard.decode([ConditionTemplate].self, from: data)
        if merge {
            var map = Dictionary(uniqueKeysWithValues: templates.map { ($0.id, $0) })
            for t in incoming { map[t.id] = t }
            templates = Array(map.values).sorted { $0.updatedAt > $1.updatedAt }
        } else {
            templates = incoming.sorted { $0.updatedAt > $1.updatedAt }
        }
    }

    // MARK: Letterheads

    func letterheadsDirectoryURL() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = docs.appendingPathComponent("Letterheads", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    func letterheadURL(named name: String) -> URL {
        letterheadsDirectoryURL().appendingPathComponent(name)
    }

    func addLetterhead(from pickedURL: URL) throws {
        let name = pickedURL.lastPathComponent
        let dest = letterheadURL(named: name)

        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.copyItem(at: pickedURL, to: dest)

        if !letterheads.contains(name) {
            letterheads.append(name)
            letterheads.sort { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        }
        if selectedLetterheadName == nil {
            selectedLetterheadName = name
        }
    }

    func deleteLetterhead(named name: String) throws {
        let url = letterheadURL(named: name)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        letterheads.removeAll { $0 == name }
        if selectedLetterheadName == name {
            selectedLetterheadName = letterheads.first
        }
    }

    // MARK: Persistence

    private func loadTemplates() {
        guard let data = UserDefaults.standard.data(forKey: templatesKey) else {
            templates = []
            return
        }
        do {
            templates = try JSONDecoder.standard.decode([ConditionTemplate].self, from: data)
        } catch {
            templates = []
        }
    }

    private func persistTemplates() {
        do {
            let data = try JSONEncoder.standard.encode(templates)
            UserDefaults.standard.set(data, forKey: templatesKey)
        } catch {
            // ignore
        }
    }

    private func loadLetterheads() {
        guard let data = UserDefaults.standard.data(forKey: letterheadsKey) else {
            letterheads = []
            selectedLetterheadName = nil
            return
        }
        do {
            let saved = try JSONDecoder.standard.decode(LetterheadState.self, from: data)
            letterheads = saved.letterheads
            selectedLetterheadName = saved.selected

            // Remove missing files
            letterheads = letterheads.filter { FileManager.default.fileExists(atPath: letterheadURL(named: $0).path) }
            if let sel = selectedLetterheadName, !letterheads.contains(sel) {
                selectedLetterheadName = letterheads.first
            }
        } catch {
            letterheads = []
            selectedLetterheadName = nil
        }
    }

    private func persistLetterheads() {
        let state = LetterheadState(letterheads: letterheads, selected: selectedLetterheadName)
        do {
            let data = try JSONEncoder.standard.encode(state)
            UserDefaults.standard.set(data, forKey: letterheadsKey)
        } catch {
            // ignore
        }
    }

    // MARK: History

    func addToHistory(level: TemplateLevel, patientName: String, entries: [PlanEntry]) {
        // Don’t store completely empty plans
        let hasAnyContent = !patientName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                            entries.contains(where: {
                                !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                                !$0.assessment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                                !$0.plan.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            })
        guard hasAnyContent else { return }

        let item = SavedPlan(level: level, patientName: patientName, entries: entries)
        history.insert(item, at: 0)
        if history.count > 5 {
            history = Array(history.prefix(5))
        }
    }

    func deleteHistory(at offsets: IndexSet) {
        history.remove(atOffsets: offsets)
    }

    func clearHistory() {
        history = []
    }

    private func loadHistory() {
        guard let data = UserDefaults.standard.data(forKey: historyKey) else {
            history = []
            return
        }
        do {
            history = try JSONDecoder.standard.decode([SavedPlan].self, from: data)
        } catch {
            history = []
        }
    }

    private func persistHistory() {
        do {
            let data = try JSONEncoder.standard.encode(history)
            UserDefaults.standard.set(data, forKey: historyKey)
        } catch {
            // ignore
        }
    }

    private func seedDefaults() {
        templates = [
            ConditionTemplate(
                title: "DRY EYE CAUSED BY\nMEIBOMIAN GLAND\nDYSFUNCTION",
                assessment: "Dry eye secondary to meibomian gland dysfunction/exposure OU.",
                plan: "Hot compresses 5–10 minutes daily, then gentle lid massage. Consider lid hygiene and preservative-free artificial tears as needed. If symptoms persist, consider anti-inflammatory dry eye treatment.",
                level: .basic,
                isPinned: true
            ),
            ConditionTemplate(
                title: "RISK OF GLAUCOMA",
                assessment: "Glaucoma suspect based on optic nerve/IOP risk factors.",
                plan: "Monitor with periodic IOP checks, optic nerve/OCT imaging, and visual field testing. Escalate to treatment/referral if progression or consistently elevated pressures.",
                level: .basic,
                isPinned: true
            ),
            ConditionTemplate(
                title: "GLAUCOMA",
                assessment: "Primary open-angle glaucoma.",
                plan: "Continue/Initiate IOP-lowering therapy as indicated. Monitor with IOP, OCT, and VF at appropriate intervals. Consider ophthalmology co-management.",
                level: .advanced,
                isPinned: false
            )
        ]
    }
}

// MARK: - Root

struct ContentView: View {
    @StateObject private var store = AppStore()

    var body: some View {
        TabView {
            NavigationStack {
                NewPlanView()
            }
            .tabItem { Label("New Plan", systemImage: "doc.text") }

            NavigationStack {
                ManageTemplatesView()
            }
            .tabItem { Label("Manage", systemImage: "slider.horizontal.3") }

            NavigationStack {
                SettingsView()
            }
            .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .environmentObject(store)
    }
}

// MARK: - New Plan

private struct NewPlanView: View {
    @EnvironmentObject private var store: AppStore

    @State private var level: TemplateLevel = .basic
    @State private var selectedTemplateID: UUID? = nil

    @State private var patientName: String = ""
    @State private var planEntries: [PlanEntry] = []

    @State private var showShareSheet = false
    @State private var exportURL: URL? = nil
    @State private var pendingDeleteEntryID: UUID? = nil
    @State private var showDeleteWarning: Bool = false
    @State private var showHistorySheet: Bool = false

    private var pinned: [ConditionTemplate] {
        store.templates
            .filter { $0.isPinned && $0.level == level }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    private var others: [ConditionTemplate] {
        store.templates
            .filter { !$0.isPinned && $0.level == level }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .navigationTitle("Tx Plan")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack {
                    Button {
                        showHistorySheet = true
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                    }

                    Button("Clear") {
                        clearForm()
                    }
                }
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = exportURL {
                ActivityView(items: [url])
            } else {
                ActivityView(items: [])
            }
        }
        .sheet(isPresented: $showHistorySheet) {
            HistorySheet(
                history: store.history,
                onRestore: { saved in
                    level = saved.level
                    patientName = saved.patientName
                    planEntries = saved.entries
                    selectedTemplateID = nil
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
    }

    private var sidebar: some View {
        VStack(spacing: 12) {
            Picker("", selection: $level) {
                ForEach(TemplateLevel.allCases) { lvl in
                    Text(lvl.displayName).tag(lvl)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 8)

            List(selection: $selectedTemplateID) {
                if !pinned.isEmpty {
                    Section("Pinned") {
                        ForEach(pinned) { t in
                            Button {
                                toggleTemplateSelection(t)
                            } label: {
                                HStack {
                                    Text(t.title)
                                        .font(.subheadline)
                                        .multilineTextAlignment(.leading)
                                    Spacer()
                                    if isTemplateSelected(t.id) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.tint)
                                    }
                                }
                            }
                        }
                    }
                }

                Section {
                    ForEach(others) { t in
                        Button {
                            toggleTemplateSelection(t)
                        } label: {
                            HStack {
                                Text(t.title)
                                    .font(.subheadline)
                                    .multilineTextAlignment(.leading)
                                Spacer()
                                if isTemplateSelected(t.id) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.tint)
                                }
                            }
                        }
                    }
                }

                Section {
                    Button {
                        addOtherEntry()
                        selectedTemplateID = nil
                    } label: {
                        Label("Other", systemImage: "plus.circle")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
    private var detail: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Patient Name", text: $patientName)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)
                .padding(.top, 8)

            if planEntries.isEmpty {
                ContentUnavailableView(
                    "No items in plan",
                    systemImage: "doc.text",
                    description: Text("Select conditions from the left panel to build the treatment plan.")
                )
                .padding(.top, 20)
            } else {
                List {
                    Section("Selected") {
                        ForEach($planEntries) { $entry in
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(alignment: .top) {
                                    if entry.templateID == nil {
                                        TextField("Condition", text: $entry.title)
                                            .textFieldStyle(.roundedBorder)
                                            .font(.headline)
                                    } else {
                                        Text(entry.title.isEmpty ? "(Untitled)" : entry.title)
                                            .font(.headline)
                                    }
                                    Spacer()
                                    Button {
                                        requestDelete(entryID: entry.id)
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                }

                                HStack(alignment: .top, spacing: 12) {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("Assessment")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        TextEditor(text: $entry.assessment)
                                            .frame(minHeight: 120)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 8)
                                                    .stroke(.secondary.opacity(0.35))
                                            )
                                    }

                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("Plan")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        TextEditor(text: $entry.plan)
                                            .frame(minHeight: 120)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 8)
                                                    .stroke(.secondary.opacity(0.35))
                                            )
                                    }
                                }
                            }
                            .padding(.vertical, 8)
                        }
                        .onMove { from, to in
                            planEntries.move(fromOffsets: from, toOffset: to)
                        }
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { EditButton() }
                }
            }

            HStack {
                Button {
                    generateAndSharePDF()
                } label: {
                    Label("Export PDF", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.borderedProminent)
                .disabled(planEntries.isEmpty)

                Spacer()

                Text("Letterhead: \(store.selectedLetterheadName ?? "none")")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding([.horizontal, .bottom])
        }
    }

    private var exportTemplates: [ConditionTemplate] {
        planEntries.map {
            ConditionTemplate(
                id: $0.templateID ?? $0.id,
                title: $0.title,
                assessment: $0.assessment,
                plan: $0.plan,
                level: level,
                isPinned: false,
                createdAt: Date(),
                updatedAt: Date()
            )
        }
    }

    private func addToPlan(templateID: UUID) {
        guard let t = store.template(id: templateID) else { return }
        if planEntries.contains(where: { $0.templateID == templateID }) { return }

        planEntries.append(
            PlanEntry(
                id: UUID(),
                templateID: templateID,
                title: t.title,
                assessment: t.assessment,
                plan: t.plan,
                originalAssessment: t.assessment,
                originalPlan: t.plan
            )
        )
    }
    private func isTemplateSelected(_ templateID: UUID) -> Bool {
        planEntries.contains(where: { $0.templateID == templateID })
    }

    private func toggleTemplateSelection(_ template: ConditionTemplate) {
        if let entry = planEntries.first(where: { $0.templateID == template.id }) {
            // tap again removes (with warning if edited)
            requestDelete(entryID: entry.id)
            selectedTemplateID = nil
        } else {
            addToPlan(templateID: template.id)
            selectedTemplateID = template.id
        }
    }
    private func addOtherEntry() {
        planEntries.append(
            PlanEntry(
                id: UUID(),
                templateID: nil,
                title: "Other",
                assessment: "",
                plan: "",
                originalAssessment: "",
                originalPlan: ""
            )
        )
    }

    private func needsDeleteWarning(for entry: PlanEntry) -> Bool {
        if entry.templateID == nil {
            let trimmedTitle = entry.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedAssessment = entry.assessment.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedPlan = entry.plan.trimmingCharacters(in: .whitespacesAndNewlines)

            let titleIsDefault = trimmedTitle.isEmpty || trimmedTitle == "Other"
            let hasEdits = !trimmedAssessment.isEmpty || !trimmedPlan.isEmpty || !titleIsDefault
            return hasEdits
        }
        return entry.assessment != entry.originalAssessment || entry.plan != entry.originalPlan
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
    }

    private func clearForm() {
        store.addToHistory(level: level, patientName: patientName, entries: planEntries)
        patientName = ""
        planEntries = []
        selectedTemplateID = nil
    }

    private func generateAndSharePDF() {
        do {
            let url = try PlanPDFBuilder.buildPDF(
                patientName: patientName,
                templates: exportTemplates,
                letterheadURL: store.selectedLetterheadName.map { store.letterheadURL(named: $0) }
            )
            exportURL = url
            showShareSheet = true
        } catch {
            // ignore for now
        }
    }
}

// MARK: - HistorySheet

private struct HistorySheet: View {
    let history: [SavedPlan]
    let onRestore: (SavedPlan) -> Void
    let onDelete: (IndexSet) -> Void
    let onClearAll: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if history.isEmpty {
                    ContentUnavailableView(
                        "No history",
                        systemImage: "clock",
                        description: Text("Cleared plans are saved here (up to 5).")
                    )
                } else {
                    List {
                        ForEach(history) { item in
                            Button {
                                onRestore(item)
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(item.patientName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "(No patient name)" : item.patientName)
                                        .font(.headline)

                                    HStack(spacing: 10) {
                                        Text(item.level.displayName)
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)

                                        Text(item.savedAt.formatted(date: .abbreviated, time: .shortened))
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)

                                        Spacer()

                                        Text("\(item.entries.count) item\(item.entries.count == 1 ? "" : "s")")
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.vertical, 6)
                            }
                        }
                        .onDelete(perform: onDelete)
                    }
                }
            }
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    if !history.isEmpty {
                        Button(role: .destructive) {
                            onClearAll()
                        } label: {
                            Text("Clear All")
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Manage Templates

private struct ManageTemplatesView: View {
    @EnvironmentObject private var store: AppStore

    @State private var query: String = ""
    @State private var level: TemplateLevel = .basic

    @State private var presentingEditor = false
    @State private var editorMode: TemplateEditorMode = .create

    private var filtered: [ConditionTemplate] {
        let base = store.templates.filter { $0.level == level }
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let list: [ConditionTemplate]

        if q.isEmpty {
            list = base.sorted { a, b in
                if a.isPinned != b.isPinned { return a.isPinned && !b.isPinned }
                return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
            }
        } else {
            list = base.filter {
                $0.title.localizedCaseInsensitiveContains(q) ||
                $0.assessment.localizedCaseInsensitiveContains(q) ||
                $0.plan.localizedCaseInsensitiveContains(q)
            }
            .sorted { $0.updatedAt > $1.updatedAt }
        }

        return list
    }

    var body: some View {
        List {
            Section {
                ForEach(filtered) { t in
                    HStack(alignment: .top, spacing: 12) {
                        Button {
                            store.togglePinned(id: t.id)
                        } label: {
                            Image(systemName: t.isPinned ? "pin.fill" : "pin")
                                .foregroundStyle(t.isPinned ? .yellow : .secondary)
                        }
                        .buttonStyle(.plain)

                        VStack(alignment: .leading, spacing: 6) {
                            Text(t.title)
                                .font(.headline)
                                .lineLimit(2)

                            if !t.assessment.isEmpty {
                                Text(t.assessment)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }

                            if !t.plan.isEmpty {
                                Text(t.plan)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }

                        Spacer()

                        Button("Edit") {
                            editorMode = .edit(id: t.id)
                            presentingEditor = true
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.vertical, 6)
                }
                .onDelete { offsets in
                    store.deleteTemplates(at: offsets, in: filtered)
                }

                if filtered.isEmpty {
                    ContentUnavailableView(
                        "No templates",
                        systemImage: "doc.text",
                        description: Text("Add templates with the + button.")
                    )
                }
            }
        }
        .navigationTitle("Manage")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Picker("", selection: $level) {
                    ForEach(TemplateLevel.allCases) { lvl in
                        Text(lvl.displayName).tag(lvl)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 240)
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editorMode = .create
                    presentingEditor = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .automatic))
        .sheet(isPresented: $presentingEditor) {
            TemplateEditorSheet(mode: editorMode, defaultLevel: level)
        }
    }
}

private enum TemplateEditorMode: Equatable {
    case create
    case edit(id: UUID)
}

private struct TemplateEditorSheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    let mode: TemplateEditorMode
    let defaultLevel: TemplateLevel

    @State private var title: String = ""
    @State private var assessment: String = ""
    @State private var plan: String = ""

    @State private var level: TemplateLevel = .basic
    @State private var isPinned: Bool = false

    @State private var loadedID: UUID? = nil

    var body: some View {
        NavigationStack {
            Form {
                Section("Title") {
                    TextField("Condition name", text: $title)
                        .textInputAutocapitalization(.sentences)
                }

                Section("Level") {
                    Picker("", selection: $level) {
                        ForEach(TemplateLevel.allCases) { lvl in
                            Text(lvl.displayName).tag(lvl)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    Toggle("Pin to top", isOn: $isPinned)
                }

                Section("Assessment") {
                    TextEditor(text: $assessment)
                        .frame(minHeight: 120)
                }

                Section("Plan") {
                    TextEditor(text: $plan)
                        .frame(minHeight: 160)
                }
            }
            .navigationTitle(modeTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear { loadIfNeeded() }
        }
    }

    private var modeTitle: String {
        switch mode {
        case .create: return "New Template"
        case .edit: return "Edit Template"
        }
    }

    private func loadIfNeeded() {
        switch mode {
        case .create:
            if loadedID == nil {
                loadedID = UUID()
                self.level = defaultLevel
                self.isPinned = false
                self.title = ""
                self.assessment = ""
                self.plan = ""
            }

        case .edit(let id):
            guard loadedID != id, let t = store.template(id: id) else { return }
            loadedID = id
            title = t.title
            assessment = t.assessment
            plan = t.plan
            level = t.level
            isPinned = t.isPinned
        }
    }

    private func save() {
        let tTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let tAssess = assessment.trimmingCharacters(in: .whitespacesAndNewlines)
        let tPlan = plan.trimmingCharacters(in: .whitespacesAndNewlines)

        switch mode {
        case .create:
            let new = ConditionTemplate(
                title: tTitle,
                assessment: tAssess,
                plan: tPlan,
                level: level,
                isPinned: isPinned,
                createdAt: Date(),
                updatedAt: Date()
            )
            store.addTemplate(new)

        case .edit(let id):
            guard var existing = store.template(id: id) else { return }
            existing.title = tTitle
            existing.assessment = tAssess
            existing.plan = tPlan
            existing.level = level
            existing.isPinned = isPinned
            existing.updatedAt = Date()
            store.updateTemplate(existing)
        }
    }
}

// MARK: - Settings

private struct SettingsView: View {
    @EnvironmentObject private var store: AppStore

    @State private var showExport = false
    @State private var exportDoc: TemplatesJSONDocument? = nil

    @State private var showImport = false
    @State private var importMerge = true

    @State private var showLetterheadImporter = false

    var body: some View {
        List {
            Section("Templates") {
                Toggle("Merge on import", isOn: $importMerge)

                Button {
                    do {
                        let data = try store.exportTemplatesJSON()
                        exportDoc = TemplatesJSONDocument(data: data)
                        showExport = true
                    } catch {
                        // ignore
                    }
                } label: {
                    Label("Export templates", systemImage: "square.and.arrow.up")
                }

                Button {
                    showImport = true
                } label: {
                    Label("Import templates", systemImage: "square.and.arrow.down")
                }
            }

            Section("Letterhead") {
                if store.letterheads.isEmpty {
                    Text("No letterhead PDFs added yet.")
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Active letterhead", selection: Binding(
                        get: { store.selectedLetterheadName },
                        set: { store.selectedLetterheadName = $0 }
                    )) {
                        Text("None").tag(String?.none)
                        ForEach(store.letterheads, id: \.self) { name in
                            Text(name).tag(String?.some(name))
                        }
                    }
                }

                Button {
                    showLetterheadImporter = true
                } label: {
                    Label("Add letterhead PDF", systemImage: "doc.badge.plus")
                }

                if !store.letterheads.isEmpty {
                    ForEach(store.letterheads, id: \.self) { name in
                        HStack {
                            Text(name)
                                .lineLimit(1)
                            Spacer()
                            Button(role: .destructive) {
                                try? store.deleteLetterhead(named: name)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .navigationTitle("Settings")
        .fileExporter(
            isPresented: $showExport,
            document: exportDoc,
            contentType: .json,
            defaultFilename: "SummaryTemplates"
        ) { _ in }
        .fileImporter(
            isPresented: $showImport,
            allowedContentTypes: [.json]
        ) { result in
            switch result {
            case .success(let url):
                do {
                    let started = url.startAccessingSecurityScopedResource()
                    defer { if started { url.stopAccessingSecurityScopedResource() } }
                    let data = try Data(contentsOf: url)
                    try store.importTemplatesJSON(data, merge: importMerge)
                } catch {
                    // ignore
                }
            case .failure:
                break
            }
        }
        .fileImporter(
            isPresented: $showLetterheadImporter,
            allowedContentTypes: [.pdf]
        ) { result in
            switch result {
            case .success(let url):
                do {
                    let started = url.startAccessingSecurityScopedResource()
                    defer { if started { url.stopAccessingSecurityScopedResource() } }
                    try store.addLetterhead(from: url)
                } catch {
                    // ignore
                }
            case .failure:
                break
            }
        }
    }
}

private struct TemplatesJSONDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        self.data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

// MARK: - PDF generation

enum PlanPDFBuilder {
    static func buildPDF(patientName: String, templates: [ConditionTemplate], letterheadURL: URL?) throws -> URL {
        let filenamePatient = patientName.trimmingCharacters(in: .whitespacesAndNewlines)
        let safeName = filenamePatient.isEmpty ? "Patient" : filenamePatient
        let outURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("TxPlan_\(safeName)_\(Int(Date().timeIntervalSince1970)).pdf")

        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792) // US Letter @ 72 dpi
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)

        let data = renderer.pdfData { ctx in
            var y: CGFloat = 0

            func beginPage() {
                ctx.beginPage()

                // Background letterhead, if provided
                if let bgURL = letterheadURL,
                   let doc = PDFDocument(url: bgURL),
                   let page = doc.page(at: 0) {
                    page.draw(with: .mediaBox, to: ctx.cgContext)
                }

                // Content start
                y = 120
            }

            func draw(_ text: String, font: UIFont, x: CGFloat, y: CGFloat, width: CGFloat) -> CGFloat {
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: font
                ]

                let nsText = text as NSString
                let rect = nsText.boundingRect(
                    with: CGSize(width: width, height: 10_000),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: attrs,
                    context: nil
                )

                let drawRect = CGRect(x: x, y: y, width: width, height: ceil(rect.height))
                nsText.draw(in: drawRect, withAttributes: attrs)
                return y + ceil(rect.height)
            }

            beginPage()

            let marginX: CGFloat = 54
            let contentWidth = pageRect.width - 2 * marginX

            y = draw("Treatment Plan", font: .boldSystemFont(ofSize: 18), x: marginX, y: y, width: contentWidth) + 10

            let patientLine = filenamePatient.isEmpty ? "Patient: __________________" : "Patient: \(filenamePatient)"
            y = draw(patientLine, font: .systemFont(ofSize: 12), x: marginX, y: y, width: contentWidth) + 14

            let dateLine = "Date: \(Date().formatted(date: .abbreviated, time: .omitted))"
            y = draw(dateLine, font: .systemFont(ofSize: 12), x: marginX, y: y, width: contentWidth) + 18

            for t in templates {
                if y > pageRect.height - 120 {
                    beginPage()
                }

                y = draw(t.title, font: .boldSystemFont(ofSize: 13), x: marginX, y: y, width: contentWidth) + 6

                let a = t.assessment.trimmingCharacters(in: .whitespacesAndNewlines)
                if !a.isEmpty {
                    y = draw("Assessment:", font: .boldSystemFont(ofSize: 11), x: marginX, y: y, width: contentWidth) + 2
                    y = draw(a, font: .systemFont(ofSize: 11), x: marginX, y: y, width: contentWidth) + 8
                }

                let p = t.plan.trimmingCharacters(in: .whitespacesAndNewlines)
                if !p.isEmpty {
                    y = draw("Plan:", font: .boldSystemFont(ofSize: 11), x: marginX, y: y, width: contentWidth) + 2
                    y = draw(p, font: .systemFont(ofSize: 11), x: marginX, y: y, width: contentWidth) + 14
                }
            }
        }

        try data.write(to: outURL, options: .atomic)
        return outURL
    }
}

// MARK: - Share sheet

private struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Preview

#Preview {
    ContentView()
}
