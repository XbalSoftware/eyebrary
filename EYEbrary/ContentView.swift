//
//  ContentView.swift
//  EYEbrary
//
//  Created by Simon Reid on 2026-03-01.
//

import SwiftUI
import Combine
import UIKit
import UniformTypeIdentifiers
import PDFKit

// MARK: - Data Model


struct CategoryItem: Identifiable, Codable, Equatable {
    var id: String
    var name: String
    var order: Int
}
// Category identifiers are user-editable (via Settings), so this is a String id.
typealias EntryCategory = String

extension EntryCategory {
    // Built-in defaults (keep stable so existing data continues to match)
    static let general: EntryCategory = "general"
    static let dryEye: EntryCategory = "dryEye"
    static let glaucoma: EntryCategory = "glaucoma"
}
private enum LegacyTemplateLevel: String, Codable {
    case basic
    case advanced
}

struct LibraryEntry: Identifiable, Codable, Equatable {
    var id: UUID = UUID()

    var title: String
    var body: String

    var category: EntryCategory = .general
    var isFavorite: Bool
    /// If false, the template is hidden from the New Report picker but remains available in Manage.
    var isVisible: Bool = true
    /// Controls display ordering (lower first). Optional for backward compatibility.
    var order: Int? = nil

    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    enum CodingKeys: String, CodingKey {
        case id, title, body, assessment, plan, category, defaultStyle, isFavorite, isPinned, isVisible, order, createdAt, updatedAt, level
    }

    init(
        id: UUID = UUID(),
        title: String,
        body: String,
        category: EntryCategory = .general,
        isFavorite: Bool,
        isVisible: Bool = true,
        order: Int? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.category = category
        self.isFavorite = isFavorite
        self.isVisible = isVisible
        self.order = order
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.title = try c.decode(String.self, forKey: .title)

        let decodedBody = try c.decodeIfPresent(String.self, forKey: .body)
        let decodedAssessment = try c.decodeIfPresent(String.self, forKey: .assessment)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let decodedPlan = try c.decodeIfPresent(String.self, forKey: .plan)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if let decodedBody, !decodedBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            self.body = decodedBody
        } else if !decodedAssessment.isEmpty && !decodedPlan.isEmpty {
            self.body = "Assessment\n\(decodedAssessment)\n\nPlan\n\(decodedPlan)"
        } else if !decodedAssessment.isEmpty {
            self.body = decodedAssessment
        } else {
            self.body = decodedPlan
        }

        _ = try? c.decode(LegacyTemplateLevel.self, forKey: .level)
        self.category = (try? c.decode(EntryCategory.self, forKey: .category)) ?? .general
        _ = try? c.decode(String.self, forKey: .defaultStyle)
        self.isFavorite = try c.decodeIfPresent(Bool.self, forKey: .isFavorite)
            ?? (try c.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false)
        self.isVisible = try c.decodeIfPresent(Bool.self, forKey: .isVisible) ?? true
        self.order = try c.decodeIfPresent(Int.self, forKey: .order)
        self.createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        self.updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(body, forKey: .body)
        try c.encode(category, forKey: .category)
        try c.encode(isFavorite, forKey: .isFavorite)
        try c.encode(isVisible, forKey: .isVisible)
        try c.encodeIfPresent(order, forKey: .order)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(updatedAt, forKey: .updatedAt)
    }
}

struct PlanEntry: Identifiable, Codable, Equatable {
    var id: UUID
    var templateID: UUID?   // nil for “Other”

    var title: String
    var originalTitle: String
    
    var body: String
    var originalBody: String
    init(
        id: UUID,
        templateID: UUID?,
        title: String,
        originalTitle: String,
        body: String,
        originalBody: String
    ) {
        self.id = id
        self.templateID = templateID
        self.title = title
        self.originalTitle = originalTitle
        self.body = body
        self.originalBody = originalBody
    }
}
extension PlanEntry {
    enum CodingKeys: String, CodingKey {
        case id, templateID, EntryID, title, originalTitle, body, originalBody, assessment, plan, originalAssessment, originalPlan
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        templateID = try c.decodeIfPresent(UUID.self, forKey: .templateID)
            ?? (try c.decodeIfPresent(UUID.self, forKey: .EntryID))
        title = try c.decode(String.self, forKey: .title)
        originalTitle = try c.decode(String.self, forKey: .originalTitle)

        let decodedBody = try c.decodeIfPresent(String.self, forKey: .body)
        let decodedOriginalBody = try c.decodeIfPresent(String.self, forKey: .originalBody)
        let decodedAssessment = try c.decodeIfPresent(String.self, forKey: .assessment)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let decodedPlan = try c.decodeIfPresent(String.self, forKey: .plan)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let decodedOriginalAssessment = try c.decodeIfPresent(String.self, forKey: .originalAssessment)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let decodedOriginalPlan = try c.decodeIfPresent(String.self, forKey: .originalPlan)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if let decodedBody, !decodedBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            body = decodedBody
        } else if !decodedAssessment.isEmpty && !decodedPlan.isEmpty {
            body = "Assessment\n\(decodedAssessment)\n\nPlan\n\(decodedPlan)"
        } else if !decodedAssessment.isEmpty {
            body = decodedAssessment
        } else {
            body = decodedPlan
        }

        if let decodedOriginalBody, !decodedOriginalBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            originalBody = decodedOriginalBody
        } else if !decodedOriginalAssessment.isEmpty && !decodedOriginalPlan.isEmpty {
            originalBody = "Assessment\n\(decodedOriginalAssessment)\n\nPlan\n\(decodedOriginalPlan)"
        } else if !decodedOriginalAssessment.isEmpty {
            originalBody = decodedOriginalAssessment
        } else {
            originalBody = decodedOriginalPlan
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encodeIfPresent(templateID, forKey: .templateID)
        try c.encode(title, forKey: .title)
        try c.encode(originalTitle, forKey: .originalTitle)
        try c.encode(body, forKey: .body)
        try c.encode(originalBody, forKey: .originalBody)
    }
}

struct SavedPlan: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var savedAt: Date = Date()

    // NOTE: Not stored for privacy when clearing a plan.
    var patientName: String

    // Stored so the report can be restored from History.
    var reportTitle: String
    var reportDate: Date

    var entries: [PlanEntry]

    enum CodingKeys: String, CodingKey {
        case id, savedAt, patientName, reportTitle, reportDate, entries
    }

    init(
        id: UUID = UUID(),
        savedAt: Date = Date(),
        patientName: String,
        reportTitle: String,
        reportDate: Date,
        entries: [PlanEntry]
    ) {
        self.id = id
        self.savedAt = savedAt
        self.patientName = patientName
        self.reportTitle = reportTitle
        self.reportDate = reportDate
        self.entries = entries
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.savedAt = try c.decodeIfPresent(Date.self, forKey: .savedAt) ?? Date()
        self.patientName = try c.decodeIfPresent(String.self, forKey: .patientName) ?? ""
        self.reportTitle = try c.decodeIfPresent(String.self, forKey: .reportTitle) ?? ""
        self.reportDate = try c.decodeIfPresent(Date.self, forKey: .reportDate) ?? Date()
        self.entries = try c.decodeIfPresent([PlanEntry].self, forKey: .entries) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(savedAt, forKey: .savedAt)
        try c.encode(patientName, forKey: .patientName)
        try c.encode(reportTitle, forKey: .reportTitle)
        try c.encode(reportDate, forKey: .reportDate)
        try c.encode(entries, forKey: .entries)
    }
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
    @Published var entries: [LibraryEntry] = [] {
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

    @Published var categories: [CategoryItem] = [] {
        didSet { persistCategories() }
    }

    private let templatesKey = "EYEbrary.conditionTemplates.v1"
    private let letterheadsKey = "EYEbrary.letterheads.v1"
    private let historyKey = "EYEbrary.history.v1"
    private let categoriesKey = "EYEbrary.categories.v1"

    init() {
        loadTemplates()
        ensureTemplateOrdering()
        loadLetterheads()
        loadHistory()
        loadCategories()
        if entries.isEmpty { seedDefaults() }
    }

    // MARK: Ordering

    private func ensureTemplateOrdering() {
        // Ensure every template has a stable order. If any are missing, assign them.
        if entries.allSatisfy({ $0.order != nil }) { return }

        // Sort in a stable, reasonable default way.
        let sorted = entries.sorted { a, b in
            if a.isFavorite != b.isFavorite { return a.isFavorite && !b.isFavorite }
            let ao = a.order ?? Int.max
            let bo = b.order ?? Int.max
            if ao != bo { return ao < bo }
            return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
        }

        for (idx, t) in sorted.enumerated() {
            if let i = entries.firstIndex(where: { $0.id == t.id }) {
                if entries[i].order == nil {
                    entries[i].order = idx
                }
            }
        }

        // Trigger persistence
        entries = entries
    }

    func applyReorder(orderedIDs: [UUID]) {
        // Reassign contiguous order values for the templates in the provided order.
        for (i, id) in orderedIDs.enumerated() {
            if let idx = entries.firstIndex(where: { $0.id == id }) {
                entries[idx].order = i
                entries[idx].updatedAt = Date()
            }
        }
    }

    func nextOrderValue() -> Int {
        let maxOrder = entries.compactMap { $0.order }.max() ?? -1
        return maxOrder + 1
    }

    // MARK: Templates

    func addEntry(_ t: LibraryEntry) {
        var new = t
        if new.order == nil {
            new.order = nextOrderValue()
        }
        entries.insert(new, at: 0)
    }

    func updateEntry(_ t: LibraryEntry) {
        guard let idx = entries.firstIndex(where: { $0.id == t.id }) else { return }
        entries[idx] = t
    }

    func deleteTemplates(at offsets: IndexSet, in filtered: [LibraryEntry]) {
        let idsToDelete = offsets.map { filtered[$0].id }
        entries.removeAll { idsToDelete.contains($0.id) }
    }

    func toggleFavorite(id: UUID) {
        guard let idx = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[idx].isFavorite.toggle()
        entries[idx].updatedAt = Date()
    }

    func toggleVisible(id: UUID) {
        guard let idx = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[idx].isVisible.toggle()
        entries[idx].updatedAt = Date()
    }

    func entry(id: UUID) -> LibraryEntry? {
        entries.first(where: { $0.id == id })
    }

    // MARK: Category normalization

    private func normalizedCategoryID(_ raw: EntryCategory) -> EntryCategory {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .general }

        let validIDs = Set(categories.map { $0.id.isEmpty ? EntryCategory.general : $0.id })
        return validIDs.contains(trimmed) ? trimmed : .general
    }

    private func normalizeImportedEntries(_ entries: [LibraryEntry]) -> [LibraryEntry] {
        entries.map { t in
            var copy = t
            copy.category = normalizedCategoryID(copy.category)
            return copy
        }
    }

    // MARK: Import/Export Templates

    func exportLibraryJSON() throws -> Data {
        try JSONEncoder.pretty.encode(entries)
    }

    func importLibraryJSON(_ data: Data, merge: Bool) throws {
        let decoded = try JSONDecoder.standard.decode([LibraryEntry].self, from: data)
        let incoming = normalizeImportedEntries(decoded)

        if merge {
            var map = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
            for t in incoming { map[t.id] = t }
            let sorted = Array(map.values).sorted { $0.updatedAt > $1.updatedAt }
            entries = sorted.enumerated().map { index, entry in
                var copy = entry
                copy.order = index
                return copy
            }
        } else {
            let sorted = incoming.sorted { $0.updatedAt > $1.updatedAt }
            entries = sorted.enumerated().map { index, entry in
                var copy = entry
                copy.order = index
                return copy
            }
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
    func bundledBlankLetterheadURL() -> URL? {
        Bundle.main.url(forResource: "Blank", withExtension: "pdf")
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
            entries = []
            return
        }
        do {
            entries = try JSONDecoder.standard.decode([LibraryEntry].self, from: data)
        } catch {
            entries = []
        }
    }

    private func persistTemplates() {
        do {
            let data = try JSONEncoder.standard.encode(entries)
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

    func addToHistory(reportTitle: String, reportDate: Date, patientName: String, entries: [PlanEntry]) {
        // Don’t store completely empty plans
        let hasAnyContent = !patientName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                            entries.contains(where: {
                                !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                                !$0.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            })
        guard hasAnyContent else { return }

        let item = SavedPlan(patientName: patientName, reportTitle: reportTitle, reportDate: reportDate, entries: entries)
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

    // MARK: Categories

    private func defaultCategories() -> [CategoryItem] {
        // Stable, built-in set. Users can customize later.
        let names: [(String, String)] = [
            ("general", "General"),
            ("anteriorSegment", "Anterior Segment"),
            ("dryEye", "Dry Eye"),
            ("glaucoma", "Glaucoma"),
            ("retina", "Retina"),
            ("refractive", "Refractive"),
            ("contactLens", "Contact Lens"),
            ("pediatrics", "Pediatrics"),
            ("neuro", "Neuro"),
            ("meds", "Meds")
        ]

        return names.enumerated().map { idx, pair in
            CategoryItem(id: pair.0, name: pair.1, order: idx)
        }
    }

    private func loadCategories() {
        guard let data = UserDefaults.standard.data(forKey: categoriesKey) else {
            categories = defaultCategories()
            return
        }
        do {
            categories = try JSONDecoder.standard.decode([CategoryItem].self, from: data)
            if categories.isEmpty {
                categories = defaultCategories()
            }
        } catch {
            categories = defaultCategories()
        }
    }

    private func persistCategories() {
        do {
            let data = try JSONEncoder.standard.encode(categories)
            UserDefaults.standard.set(data, forKey: categoriesKey)
        } catch {
            // ignore
        }
    }

    private func factoryDefaultTemplates() -> [LibraryEntry] {
        [
            LibraryEntry(
                title: "DRY EYE CAUSED BY\nMEIBOMIAN GLAND\nDYSFUNCTION",
                body: "Dry eye secondary to meibomian gland dysfunction/exposure OU.\n\nHot compresses 5–10 minutes daily, then gentle lid massage. Consider lid hygiene and preservative-free artificial tears as needed. If symptoms persist, consider anti-inflammatory dry eye treatment.",
                category: "dryEye",
                isFavorite: true,
                isVisible: true,
                order: 0
            ),
            LibraryEntry(
                title: "RISK OF GLAUCOMA",
                body: "Glaucoma suspect based on optic nerve/IOP risk factors.\n\nMonitor with periodic IOP checks, optic nerve/OCT imaging, and visual field testing. Escalate to treatment/referral if progression or consistently elevated pressures.",
                category: "glaucoma",
                isFavorite: true,
                isVisible: true,
                order: 1
            ),
            LibraryEntry(
                title: "GLAUCOMA",
                body: "Primary open-angle glaucoma.\n\nContinue/Initiate IOP-lowering therapy as indicated. Monitor with IOP, OCT, and VF at appropriate intervals. Consider ophthalmology co-management.",
                category: "glaucoma",
                isFavorite: false,
                isVisible: true,
                order: 2
            )
        ]
    }

    private func seedDefaults() {
        if categories.isEmpty {
            categories = defaultCategories()
        }
        entries = factoryDefaultTemplates()
    }

    func resetToFactoryDefaults() {
        // Remove persisted state
        UserDefaults.standard.removeObject(forKey: templatesKey)
        UserDefaults.standard.removeObject(forKey: letterheadsKey)
        UserDefaults.standard.removeObject(forKey: historyKey)
        UserDefaults.standard.removeObject(forKey: categoriesKey)

        // Delete any saved letterhead PDF files
        let dir = letterheadsDirectoryURL()
        if let items = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
            for url in items {
                try? FileManager.default.removeItem(at: url)
            }
        }

        // Reset in-memory state (these will repersist fresh)
        history = []
        letterheads = []
        selectedLetterheadName = nil

        entries = factoryDefaultTemplates()
        ensureTemplateOrdering()
        categories = defaultCategories()
    }
}

// MARK: - Root

struct ContentView: View {
    @StateObject private var store = AppStore()

    var body: some View {
        TabView {
            NavigationStack {
                NewReportView()
            }
            .tabItem { Label("New Report", systemImage: "doc.text") }

            NavigationStack {
                ManageLibraryView()
            }
            .tabItem { Label("Library", systemImage: "slider.horizontal.3") }

            NavigationStack {
                SettingsView()
            }
            .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .environmentObject(store)
    }
}

// MARK: - New Report

private struct NewReportView: View {
    @EnvironmentObject private var store: AppStore

    @State private var selectedEntryID: UUID? = nil
    @State private var categoryFilter: CategoryFilter = .all

    // Sidebar search (New Report)
    @State private var query: String = ""
    // BRIDGE_TEST: ok

    @State private var reportTitle: String = ""

    private let reportTitlePresets: [String] = [
        "Eye Exam Summary",
        "Patient Information",
        "Topics Discussed"
    ]
    @State private var patientName: String = ""
    @State private var reportDate: Date = Date()
    @State private var planEntries: [PlanEntry] = []

    @State private var shareItem: ShareItem? = nil
    @State private var pendingDeleteEntryID: UUID? = nil
    @State private var showDeleteWarning: Bool = false
    @State private var showHistorySheet: Bool = false

    private var pinned: [LibraryEntry] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = store.entries
            .filter { $0.isFavorite && $0.isVisible && matchesCategory($0, filter: categoryFilter) }
        let filtered = q.isEmpty ? base : base.filter {
            $0.title.localizedCaseInsensitiveContains(q) ||
            $0.body.localizedCaseInsensitiveContains(q)
        }

        return filtered.sorted { (a, b) in
            let ao = a.order ?? Int.max
            let bo = b.order ?? Int.max
            if ao != bo { return ao < bo }
            return a.updatedAt > b.updatedAt
        }
    }

    private var others: [LibraryEntry] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = store.entries
            .filter { !$0.isFavorite && $0.isVisible && matchesCategory($0, filter: categoryFilter) }
        let filtered = q.isEmpty ? base : base.filter {
            $0.title.localizedCaseInsensitiveContains(q) ||
            $0.body.localizedCaseInsensitiveContains(q)
        }

        return filtered.sorted { (a, b) in
            let ao = a.order ?? Int.max
            let bo = b.order ?? Int.max
            if ao != bo { return ao < bo }
            return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
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
        .sheet(item: $shareItem) { item in
            ActivityView(items: [item.url])
        }
        .sheet(isPresented: $showHistorySheet) {
            HistorySheet(
                history: store.history,
                onRestore: { saved in
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
    }

    private var sidebar: some View {
        VStack(spacing: 12) {
            HStack {
                Spacer()

                Text("Library")
                    .font(.system(size: 20, weight: .bold))

                Spacer()

                Button {
                    addOtherEntry()
                } label: {
                    Label("Add Other", systemImage: "plus")
                        .labelStyle(.iconOnly)
                        .font(.system(size: 18, weight: .semibold))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal)
            .padding(.top, 8)

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

                if !pinned.isEmpty {
                    Section("Favorites") {
                        ForEach(pinned) { t in
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
    private var detail: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    TextField("Report Title", text: $reportTitle)
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
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.secondary.opacity(0.12))
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Choose a report title")
                }

                HStack(spacing: 12) {
                    TextField("Patient Name", text: $patientName)
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
            .padding(.top, 8)

            if planEntries.isEmpty {
                ContentUnavailableView(
                    "No entries selected",
                    systemImage: "doc.text",
                    description: Text("Select library entries from the left panel to build the report.")
                )
                .padding(.top, 20)
            } else {
                List {
                    Section("Selected") {
                        ForEach($planEntries) { $entry in
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(alignment: .top) {
                                    TextField("Entry title", text: $entry.title)
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

                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Content")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    TextEditor(text: $entry.body)
                                        .frame(minHeight: 180)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(.secondary.opacity(0.35))
                                        )
                                }
                            }
                            .padding(.vertical, 8)
                        }
                        .onMove { from, to in
                            planEntries.move(fromOffsets: from, toOffset: to)
                        }
                    }
                }
                // Keep reorder handles visible without a separate Edit button
                .environment(\.editMode, .constant(.active))
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
                    HStack(spacing: 6) {
                        Image(systemName: "doc.text")
                        Text(store.selectedLetterheadName ?? "Blank (Built-in)")
                            .lineLimit(1)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.secondary.opacity(0.12))
                    )
                }
            }
            .padding([.horizontal, .bottom])
        }
    }
    private func addToPlan(templateID: UUID) {
        guard let t = store.entry(id: templateID) else { return }
        if planEntries.contains(where: { $0.templateID == templateID }) { return }

        planEntries.append(
            PlanEntry(
                id: UUID(),
                templateID: templateID,
                title: t.title,
                originalTitle: t.title,
                body: t.body,
                originalBody: t.body
            )
        )
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
        planEntries.append(
            PlanEntry(
                id: UUID(),
                templateID: nil,
                title: "Other",
                originalTitle: "Other",
                body: "",
                originalBody: ""
            )
        )
    }
    private func needsDeleteWarning(for entry: PlanEntry) -> Bool {
        if entry.templateID == nil {
            let trimmedTitle = entry.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedBody = entry.body.trimmingCharacters(in: .whitespacesAndNewlines)

            let titleIsDefault = trimmedTitle.isEmpty || trimmedTitle == "Other"
            let hasEdits = !trimmedBody.isEmpty || !titleIsDefault
            return hasEdits
        }
        return entry.body != entry.originalBody
            || entry.title != entry.originalTitle
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
        // Privacy: do not store patient name in history.
        store.addToHistory(reportTitle: reportTitle, reportDate: reportDate, patientName: "", entries: planEntries)

        // Clear form fields.
        reportTitle = ""
        patientName = ""
        reportDate = Date()
        planEntries = []
        selectedEntryID = nil
    }

    private func generateAndSharePDF() {
        do {
            let url = try PlanPDFBuilder.buildPDF(
                patientName: patientName,
                reportTitle: reportTitle,
                reportDate: reportDate,
                entries: planEntries,
                letterheadURL: store.selectedLetterheadName.map { store.letterheadURL(named: $0) } ?? store.bundledBlankLetterheadURL()
            )
            shareItem = ShareItem(url: url)
        } catch {
            print("PDF export failed:", error)
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


// MARK: - Filtering Helpers

private enum CategoryFilter: Equatable {
    case all
    case category(EntryCategory)

    func displayName(using store: AppStore) -> String {
        switch self {
        case .all:
            return "All Categories"
        case .category(let id):
            if id == .general { return "General" }
            if let item = store.categories.first(where: { ($0.id.isEmpty ? EntryCategory.general : $0.id) == id }) {
                return item.name
            }
            // Fallback if missing
            return "General"
        }
    }
}

private func matchesCategory(_ t: LibraryEntry, filter: CategoryFilter) -> Bool {
    switch filter {
    case .all:
        return true
    case .category(let id):
        return t.category == id
    }
}
// MARK: - Manage Library

private struct ManageLibraryView: View {
    @EnvironmentObject private var store: AppStore

    @State private var query: String = ""
    @State private var categoryFilter: CategoryFilter = .all
    @State private var selectedID: UUID? = nil
    @State private var pendingDeleteEntryID: UUID? = nil
    @State private var showDeleteEntryConfirm: Bool = false
    @State private var showCreateEntrySheet: Bool = false
    @State private var detailIsEditing: Bool = false
    @State private var detailHasUnsavedChanges: Bool = false
    @State private var pendingSelectionID: UUID? = nil
    @State private var showDiscardChangesAlert: Bool = false

    private var filtered: [LibraryEntry] {
        let base = store.entries.filter { matchesCategory($0, filter: categoryFilter) }
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)

        let list: [LibraryEntry]
        if q.isEmpty {
            list = base.sorted { a, b in
                // Use ordering first; keep pinned grouped visually above non-pinned.
                if a.isFavorite != b.isFavorite { return a.isFavorite && !b.isFavorite }
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
                if a.isFavorite != b.isFavorite { return a.isFavorite && !b.isFavorite }
                let ao = a.order ?? Int.max
                let bo = b.order ?? Int.max
                if ao != bo { return ao < bo }
                return a.updatedAt > b.updatedAt
            }
        }
        return list
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
                if let pending = pendingSelectionID {
                    selectedID = pending
                }
                pendingSelectionID = nil
                detailIsEditing = false
                detailHasUnsavedChanges = false
            }
            Button("Cancel", role: .cancel) {
                pendingSelectionID = nil
            }
        } message: {
            Text("Any unsaved changes will be lost if you leave this entry without saving.")
        }
        .sheet(isPresented: $showCreateEntrySheet) {
            EntryEditorSheet(mode: .create)
                .environmentObject(store)
        }
    }

    private var manageSidebar: some View {
        VStack(spacing: 12) {
            manageHeader
            manageCategoryChips
            manageSearch
            manageEntriesList
        }
        .padding(.bottom, 8)
    }

    private var manageHeader: some View {
        HStack(spacing: 12) {
            Spacer()

            Text("Library")
                .font(.system(size: 20, weight: .bold))

            Spacer()

            Button {
                showCreateEntrySheet = true
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
        List(selection: $selectedID) {
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

            Text(t.title)
                .font(.subheadline)
                .lineLimit(2)
                .layoutPriority(1)

            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard selectedID != t.id else { return }

            if detailIsEditing && detailHasUnsavedChanges {
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
    @State private var showDeleteConfirm: Bool = false

    let entry: LibraryEntry

    @State private var title: String = ""
    @State private var bodyText: String = ""
    @State private var category: EntryCategory = .general
    @State private var isFavorite: Bool = false
    @State private var isVisible: Bool = true

    @State private var didLoad = false

    @State private var isEditing: Bool = false

    @State private var originalTitle: String = ""
    @State private var originalBodyText: String = ""
    @State private var originalCategory: EntryCategory = .general
    @State private var originalIsFavorite: Bool = false
    @State private var originalIsVisible: Bool = true

    private var bodyFieldLabel: String {
        "Entry Content"
    }

    private var hasUnsavedChanges: Bool {
        title != originalTitle
            || bodyText != originalBodyText
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
                    Button("Done") {
                        commitEdits()
                        isEditing = false
                        isEditingExternal = false
                        hasUnsavedChangesExternal = false
                    }
                    .buttonStyle(.bordered)

                    Button("Cancel") {
                        discardEdits()
                        isEditing = false
                        isEditingExternal = false
                        hasUnsavedChangesExternal = false
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
                Text(bodyFieldLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: $bodyText)
                    .disabled(!isEditing)
                    .frame(minHeight: 260)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(.secondary.opacity(0.35))
                    )
            }
            .padding(.horizontal)

            Spacer()

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
                .padding(.bottom, 12)
            }
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
        }
        .onChange(of: entry.id) { _, _ in
            didLoad = false
            isEditing = false
            isEditingExternal = false
            hasUnsavedChangesExternal = false
            loadIfNeeded()
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
        .onChange(of: bodyText) { _, _ in
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
        bodyText = entry.body
        category = entry.category
        originalCategory = entry.category
        isFavorite = entry.isFavorite
        isVisible = entry.isVisible
        originalIsFavorite = entry.isFavorite
        originalIsVisible = entry.isVisible

        // Capture originals so Cancel can revert.
        originalTitle = entry.title
        originalBodyText = entry.body
    }

    private func beginEditing() {
        // Refresh originals from the current stored version.
        guard let t = store.entry(id: entry.id) else { return }
        originalTitle = t.title
        originalBodyText = t.body
        originalCategory = t.category
        originalIsFavorite = t.isFavorite
        originalIsVisible = t.isVisible

        title = t.title
        bodyText = t.body
        category = t.category
        isFavorite = t.isFavorite
        isVisible = t.isVisible
    }

    private func discardEdits() {
        title = originalTitle
        bodyText = originalBodyText
        category = originalCategory
        isFavorite = originalIsFavorite
        isVisible = originalIsVisible
        isEditingExternal = false
        hasUnsavedChangesExternal = false
    }

    private func commitEdits() {
        guard didLoad else { return }
        guard var t = store.entry(id: entry.id) else { return }

        t.title = title
        t.body = bodyText
        t.category = category
        t.isFavorite = isFavorite
        t.isVisible = isVisible

        t.updatedAt = Date()
        store.updateEntry(t)

        // Update originals after saving.
        originalTitle = t.title
        originalBodyText = t.body
        originalCategory = t.category
        originalIsFavorite = t.isFavorite
        originalIsVisible = t.isVisible
        isEditingExternal = false
        hasUnsavedChangesExternal = false
    }
}

private enum EntryEditorMode: Equatable {
    case create
    case edit(id: UUID)
}

private struct EntryEditorSheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    let mode: EntryEditorMode

    @State private var title: String = ""
    @State private var bodyText: String = ""

    @State private var category: EntryCategory = .general
    @State private var isFavorite: Bool = false
    @State private var isVisible: Bool = true

    @State private var loadedID: UUID? = nil

    private var navigationTitle: String {
        switch mode {
        case .create:
            return "New Entry"
        case .edit:
            return "Edit Entry"
        }
    }

    private var actionTitle: String {
        switch mode {
        case .create:
            return "Create"
        case .edit:
            return "Save"
        }
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Entry") {
                    TextField("Entry title", text: $title)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled(true)

                    Picker("Category", selection: $category) {
                        let cats = store.categories.sorted { $0.order < $1.order }
                        ForEach(cats) { item in
                            Text(item.name).tag(item.id.isEmpty ? EntryCategory.general : item.id)
                        }
                    }

                    Toggle("Favorite", isOn: $isFavorite)
                    Toggle("Visible in New Report", isOn: $isVisible)
                }

                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Entry Content")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextEditor(text: $bodyText)
                            .frame(minHeight: 260)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(.secondary.opacity(0.35))
                            )
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(actionTitle) {
                        save()
                    }
                    .disabled(!canSave)
                }
            }
            .onAppear {
                loadIfNeeded()
            }
        }
    }

    private func loadIfNeeded() {
        switch mode {
        case .create:
            guard loadedID == nil else { return }
            loadedID = UUID()
            title = ""
            bodyText = ""
            category = .general
            isFavorite = false
            isVisible = true

        case .edit(let id):
            guard loadedID != id else { return }
            guard let entry = store.entry(id: id) else { return }
            loadedID = id
            title = entry.title
            bodyText = entry.body
            category = entry.category
            isFavorite = entry.isFavorite
            isVisible = entry.isVisible
            // defaultStyle = entry.defaultStyle
        }
    }

    private func save() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBody = bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty, !trimmedBody.isEmpty else { return }

        switch mode {
        case .create:
            let entry = LibraryEntry(
                title: trimmedTitle,
                body: trimmedBody,
                category: category,
                // defaultStyle: defaultStyle,
                isFavorite: isFavorite,
                isVisible: isVisible,
                order: store.nextOrderValue(),
                createdAt: Date(),
                updatedAt: Date()
            )
            store.addEntry(entry)

        case .edit(let id):
            guard var existingEntry = store.entry(id: id) else { return }
            existingEntry.title = trimmedTitle
            existingEntry.body = trimmedBody
            existingEntry.category = category
            existingEntry.isFavorite = isFavorite
            existingEntry.isVisible = isVisible
            existingEntry.updatedAt = Date()
            store.updateEntry(existingEntry)
        }

        dismiss()
    }
}

// MARK: - Settings

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

private struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var showingImporter = false
    @State private var importErrorMessage: String?
    @State private var showResetConfirm = false
    @State private var pendingImportMode: TemplateImportMode?
    @State private var showImportModeDialog = false
    @State private var importSuccessMessage: String?

    var body: some View {
        Form {
            Section("Letterhead") {
                if let selected = store.selectedLetterheadName {
                    Text("Selected: \(selected)")
                } else {
                    Text("Selected: Blank (Built-in)")
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
                showingImporter = true
            }
            Button(TemplateImportMode.replace.title, role: .destructive) {
                pendingImportMode = .replace
                showingImporter = true
            }
            Button("Cancel", role: .cancel) {
                pendingImportMode = nil
            }
        } message: {
            Text("Choose how to import the selected library file.")
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            do {
                let urls = try result.get()
                guard let url = urls.first else { return }

                let didStartAccessing = url.startAccessingSecurityScopedResource()
                defer {
                    if didStartAccessing {
                        url.stopAccessingSecurityScopedResource()
                    }
                }

                let data = try Data(contentsOf: url)
                let mode = pendingImportMode ?? .merge
                let importedTemplates = try JSONDecoder.standard.decode([LibraryEntry].self, from: data)

                let existingIDs = Set(store.entries.map { $0.id })
                let incomingIDs = Set(importedTemplates.map { $0.id })
                let addedCount = incomingIDs.subtracting(existingIDs).count
                let updatedCount = incomingIDs.intersection(existingIDs).count

                try store.importLibraryJSON(data, merge: mode == .merge)

                switch mode {
                case .merge:
                    importSuccessMessage = "Merged \(incomingIDs.count) entr\(incomingIDs.count == 1 ? "y" : "ies"): \(addedCount) added, \(updatedCount) updated."
                case .replace:
                    importSuccessMessage = "Replaced the current library with \(importedTemplates.count) entr\(importedTemplates.count == 1 ? "y" : "ies")."
                }

                pendingImportMode = nil
            } catch {
                importErrorMessage = error.localizedDescription
                pendingImportMode = nil
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

// MARK: - Sharing helpers

private struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

private struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - PDF builder

private enum PlanPDFBuilder {
    static func buildPDF(
        patientName: String,
        reportTitle: String,
        reportDate: Date,
        entries: [PlanEntry],
        letterheadURL: URL?
    ) throws -> URL {
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("EYEbrary-Report.pdf")

        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)

        try renderer.writePDF(to: outputURL) { context in
            context.beginPage()

            if let letterheadURL,
               let pdfDoc = PDFDocument(url: letterheadURL),
               let page = pdfDoc.page(at: 0) {
                page.draw(with: .mediaBox, to: context.cgContext)
            }

            let margin: CGFloat = 54
            var y: CGFloat = 72
            let contentWidth = pageRect.width - (margin * 2)

            let title = reportTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Eye Exam Summary" : reportTitle
            let headingFont = UIFont.systemFont(ofSize: 22, weight: .bold)
            let subheadingFont = UIFont.systemFont(ofSize: 12, weight: .semibold)
            let bodyFont = UIFont.systemFont(ofSize: 11)

            (title as NSString).draw(in: CGRect(x: margin, y: y, width: contentWidth, height: 28), withAttributes: [
                .font: headingFont
            ])
            y += 32

            let metaText = [
                patientName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : "Patient: \(patientName)",
                "Date: \(reportDate.formatted(date: .abbreviated, time: .omitted))"
            ].compactMap { $0 }.joined(separator: "    ")

            (metaText as NSString).draw(in: CGRect(x: margin, y: y, width: contentWidth, height: 18), withAttributes: [
                .font: subheadingFont,
                .foregroundColor: UIColor.darkGray
            ])
            y += 28

            for entry in entries {
                let entryTitle = entry.title.trimmingCharacters(in: .whitespacesAndNewlines)
                let entryBody = entry.body.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !entryTitle.isEmpty || !entryBody.isEmpty else { continue }

                if y > pageRect.height - 120 {
                    context.beginPage()
                    y = 72
                }

                if !entryTitle.isEmpty {
                    (entryTitle as NSString).draw(in: CGRect(x: margin, y: y, width: contentWidth, height: 20), withAttributes: [
                        .font: UIFont.systemFont(ofSize: 13, weight: .bold)
                    ])
                    y += 22
                }

                let bodyRect = CGRect(x: margin, y: y, width: contentWidth, height: 1000)
                let bodyString = NSAttributedString(string: entryBody, attributes: [
                    .font: bodyFont,
                    .foregroundColor: UIColor.black
                ])
                let framesetter = CTFramesetterCreateWithAttributedString(bodyString)
                let suggested = CTFramesetterSuggestFrameSizeWithConstraints(
                    framesetter,
                    CFRange(location: 0, length: bodyString.length),
                    nil,
                    CGSize(width: contentWidth, height: .greatestFiniteMagnitude),
                    nil
                )
                bodyString.draw(with: CGRect(x: bodyRect.minX, y: bodyRect.minY, width: contentWidth, height: ceil(suggested.height) + 4), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
                y += ceil(suggested.height) + 18
            }
        }

        return outputURL
    }
}
