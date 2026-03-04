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
enum TemplateCategory: String, Codable, CaseIterable, Identifiable {
    case general
    case anteriorSegment
    case dryEye
    case glaucoma
    case retina
    case refractive
    case contactLens
    case pediatrics
    case neuro
    case meds

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .general: return "General"
        case .anteriorSegment: return "Anterior Segment"
        case .dryEye: return "Dry Eye"
        case .glaucoma: return "Glaucoma"
        case .retina: return "Retina"
        case .refractive: return "Refractive"
        case .contactLens: return "Contact Lens"
        case .pediatrics: return "Pediatrics"
        case .neuro: return "Neuro"
        case .meds: return "Meds"
        }
    }
}
struct ConditionTemplate: Identifiable, Codable, Equatable {
    var id: UUID = UUID()

    var title: String
    var assessment: String
    var plan: String

    var level: TemplateLevel
    var category: TemplateCategory = .general
    var defaultStyle: PlanEntryStyle = .clinical
    var isPinned: Bool
    /// If false, the template is hidden from the New Plan picker but remains available in Manage.
    var isVisible: Bool = true
    /// Controls display ordering within a level (lower first). Optional for backward compatibility.
    var order: Int? = nil

    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    enum CodingKeys: String, CodingKey {
        case id, title, assessment, plan, level, category, defaultStyle, isPinned, isVisible, order, createdAt, updatedAt
    }

    init(
        id: UUID = UUID(),
        title: String,
        assessment: String,
        plan: String,
        level: TemplateLevel,
        category: TemplateCategory = .general,
        defaultStyle: PlanEntryStyle = .clinical,
        isPinned: Bool,
        isVisible: Bool = true,
        order: Int? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.assessment = assessment
        self.plan = plan
        self.level = level
        self.category = category
        self.defaultStyle = defaultStyle
        self.isPinned = isPinned
        self.isVisible = isVisible
        self.order = order
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.title = try c.decode(String.self, forKey: .title)
        self.assessment = try c.decode(String.self, forKey: .assessment)
        self.plan = try c.decode(String.self, forKey: .plan)
        self.level = try c.decode(TemplateLevel.self, forKey: .level)
        self.category = (try? c.decode(TemplateCategory.self, forKey: .category)) ?? .general
        self.defaultStyle = (try? c.decode(PlanEntryStyle.self, forKey: .defaultStyle)) ?? .clinical
        self.isPinned = try c.decode(Bool.self, forKey: .isPinned)
        self.isVisible = try c.decodeIfPresent(Bool.self, forKey: .isVisible) ?? true
        self.order = try c.decodeIfPresent(Int.self, forKey: .order)
        self.createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        self.updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(assessment, forKey: .assessment)
        try c.encode(plan, forKey: .plan)
        try c.encode(level, forKey: .level)
        try c.encode(category, forKey: .category)
        try c.encode(defaultStyle, forKey: .defaultStyle)
        try c.encode(isPinned, forKey: .isPinned)
        try c.encode(isVisible, forKey: .isVisible)
        try c.encodeIfPresent(order, forKey: .order)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(updatedAt, forKey: .updatedAt)
    }
}
enum PlanEntryStyle: String, Codable, CaseIterable, Identifiable {
    case clinical
    case education

    var id: String { rawValue }

    var leftLabel: String {
        switch self {
        case .clinical: return "Assessment"
        case .education: return "Overview"
        }
    }

    var rightLabel: String {
        switch self {
        case .clinical: return "Plan"
        case .education: return "Treatment Options"
        }
    }

    var menuTitle: String {
        switch self {
        case .clinical: return "Assessment / Plan"
        case .education: return "Overview / Treatment Options"
        }
    }
}
struct PlanEntry: Identifiable, Codable, Equatable {
    var id: UUID
    var templateID: UUID?   // nil for “Other”

    var title: String
    var originalTitle: String

    var style: PlanEntryStyle = .clinical
    var originalStyle: PlanEntryStyle = .clinical
    
    var assessment: String
    var plan: String
    var originalAssessment: String
    var originalPlan: String
}
extension PlanEntry {
    enum CodingKeys: String, CodingKey {
        case id, templateID, title, originalTitle, style, originalStyle, assessment, plan, originalAssessment, originalPlan
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        templateID = try? c.decode(UUID.self, forKey: .templateID)
        title = try c.decode(String.self, forKey: .title)
        originalTitle = try c.decode(String.self, forKey: .originalTitle)
        style = (try? c.decode(PlanEntryStyle.self, forKey: .style)) ?? .clinical
        originalStyle = (try? c.decode(PlanEntryStyle.self, forKey: .originalStyle)) ?? style
        assessment = try c.decode(String.self, forKey: .assessment)
        plan = try c.decode(String.self, forKey: .plan)
        originalAssessment = try c.decode(String.self, forKey: .originalAssessment)
        originalPlan = try c.decode(String.self, forKey: .originalPlan)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encodeIfPresent(templateID, forKey: .templateID)
        try c.encode(title, forKey: .title)
        try c.encode(originalTitle, forKey: .originalTitle)
        try c.encode(style, forKey: .style)
        try c.encode(originalStyle, forKey: .originalStyle)
        try c.encode(assessment, forKey: .assessment)
        try c.encode(plan, forKey: .plan)
        try c.encode(originalAssessment, forKey: .originalAssessment)
        try c.encode(originalPlan, forKey: .originalPlan)
    }
}

struct SavedPlan: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var savedAt: Date = Date()
    var level: TemplateLevel

    // NOTE: Not stored for privacy when clearing a plan.
    var patientName: String

    // Stored so the report can be restored from History.
    var reportTitle: String
    var reportDate: Date

    var entries: [PlanEntry]

    enum CodingKeys: String, CodingKey {
        case id, savedAt, level, patientName, reportTitle, reportDate, entries
    }

    init(
        id: UUID = UUID(),
        savedAt: Date = Date(),
        level: TemplateLevel,
        patientName: String,
        reportTitle: String,
        reportDate: Date,
        entries: [PlanEntry]
    ) {
        self.id = id
        self.savedAt = savedAt
        self.level = level
        self.patientName = patientName
        self.reportTitle = reportTitle
        self.reportDate = reportDate
        self.entries = entries
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.savedAt = try c.decodeIfPresent(Date.self, forKey: .savedAt) ?? Date()
        self.level = try c.decode(TemplateLevel.self, forKey: .level)
        self.patientName = try c.decodeIfPresent(String.self, forKey: .patientName) ?? ""
        self.reportTitle = try c.decodeIfPresent(String.self, forKey: .reportTitle) ?? ""
        self.reportDate = try c.decodeIfPresent(Date.self, forKey: .reportDate) ?? Date()
        self.entries = try c.decodeIfPresent([PlanEntry].self, forKey: .entries) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(savedAt, forKey: .savedAt)
        try c.encode(level, forKey: .level)
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
        ensureTemplateOrdering()
        loadLetterheads()
        loadHistory()
        if templates.isEmpty { seedDefaults() }
    }

    // MARK: Ordering

    private func ensureTemplateOrdering() {
        // Assign stable ordering for any templates missing `order`.
        var changed = false
        for lvl in TemplateLevel.allCases {
            let inLevel = templates
                .filter { $0.level == lvl }
                .sorted { a, b in
                    // If both have order use it, otherwise fall back to pinned then title.
                    let ao = a.order ?? Int.max
                    let bo = b.order ?? Int.max
                    if ao != bo { return ao < bo }
                    if a.isPinned != b.isPinned { return a.isPinned && !b.isPinned }
                    return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
                }

            var next = 0
            for t in inLevel {
                if let idx = templates.firstIndex(where: { $0.id == t.id }) {
                    if templates[idx].order == nil {
                        templates[idx].order = next
                        changed = true
                    }
                    next += 1
                }
            }
        }

        if changed {
            // Trigger persistence
            templates = templates
        }
    }

    func applyReorder(level: TemplateLevel, orderedIDs: [UUID]) {
        // Reassign contiguous order values within a level.
        for (i, id) in orderedIDs.enumerated() {
            if let idx = templates.firstIndex(where: { $0.id == id && $0.level == level }) {
                templates[idx].order = i
                templates[idx].updatedAt = Date()
            }
        }
    }

    func nextOrderValue(for level: TemplateLevel) -> Int {
        let maxOrder = templates
            .filter { $0.level == level }
            .compactMap { $0.order }
            .max() ?? -1
        return maxOrder + 1
    }

    // MARK: Templates

    func addTemplate(_ t: ConditionTemplate) {
        var new = t
        if new.order == nil {
            new.order = nextOrderValue(for: new.level)
        }
        templates.insert(new, at: 0)
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

    func toggleVisible(id: UUID) {
        guard let idx = templates.firstIndex(where: { $0.id == id }) else { return }
        templates[idx].isVisible.toggle()
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

    func addToHistory(level: TemplateLevel, reportTitle: String, reportDate: Date, patientName: String, entries: [PlanEntry]) {
        // Don’t store completely empty plans
        let hasAnyContent = !patientName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                            entries.contains(where: {
                                !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                                !$0.assessment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                                !$0.plan.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            })
        guard hasAnyContent else { return }

        let item = SavedPlan(level: level, patientName: patientName, reportTitle: reportTitle, reportDate: reportDate, entries: entries)
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

    private func factoryDefaultTemplates() -> [ConditionTemplate] {
        [
            ConditionTemplate(
                title: "DRY EYE CAUSED BY\nMEIBOMIAN GLAND\nDYSFUNCTION",
                assessment: "Dry eye secondary to meibomian gland dysfunction/exposure OU.",
                plan: "Hot compresses 5–10 minutes daily, then gentle lid massage. Consider lid hygiene and preservative-free artificial tears as needed. If symptoms persist, consider anti-inflammatory dry eye treatment.",
                level: .basic,
                category: .dryEye,
                defaultStyle: .clinical,
                isPinned: true,
                isVisible: true,
                order: 0
            ),
            ConditionTemplate(
                title: "RISK OF GLAUCOMA",
                assessment: "Glaucoma suspect based on optic nerve/IOP risk factors.",
                plan: "Monitor with periodic IOP checks, optic nerve/OCT imaging, and visual field testing. Escalate to treatment/referral if progression or consistently elevated pressures.",
                level: .basic,
                category: .glaucoma,
                defaultStyle: .clinical,
                isPinned: true,
                isVisible: true,
                order: 1
            ),
            ConditionTemplate(
                title: "GLAUCOMA",
                assessment: "Primary open-angle glaucoma.",
                plan: "Continue/Initiate IOP-lowering therapy as indicated. Monitor with IOP, OCT, and VF at appropriate intervals. Consider ophthalmology co-management.",
                level: .advanced,
                category: .glaucoma,
                defaultStyle: .clinical,
                isPinned: false,
                isVisible: true,
                order: 2
            )
        ]
    }

    private func seedDefaults() {
        templates = factoryDefaultTemplates()
    }

    func resetToFactoryDefaults() {
        // Remove persisted state
        UserDefaults.standard.removeObject(forKey: templatesKey)
        UserDefaults.standard.removeObject(forKey: letterheadsKey)
        UserDefaults.standard.removeObject(forKey: historyKey)

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

        templates = factoryDefaultTemplates()
        ensureTemplateOrdering()
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

    @State private var selectedTemplateID: UUID? = nil
    @State private var level: TemplateLevel = .basic
    @State private var category: TemplateCategory = .general

    // Sidebar search (New Plan)
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

    private var pinned: [ConditionTemplate] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = store.templates
            .filter { $0.isPinned && $0.isVisible && $0.level == level && (category == .general || $0.category == category) }

        let filtered = q.isEmpty ? base : base.filter {
            $0.title.localizedCaseInsensitiveContains(q) ||
            $0.assessment.localizedCaseInsensitiveContains(q) ||
            $0.plan.localizedCaseInsensitiveContains(q)
        }

        return filtered.sorted { (a, b) in
            let ao = a.order ?? Int.max
            let bo = b.order ?? Int.max
            if ao != bo { return ao < bo }
            return a.updatedAt > b.updatedAt
        }
    }

    private var others: [ConditionTemplate] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = store.templates
            .filter { !$0.isPinned && $0.isVisible && $0.level == level && (category == .general || $0.category == category) }

        let filtered = q.isEmpty ? base : base.filter {
            $0.title.localizedCaseInsensitiveContains(q) ||
            $0.assessment.localizedCaseInsensitiveContains(q) ||
            $0.plan.localizedCaseInsensitiveContains(q)
        }

        return filtered.sorted { (a, b) in
            let ao = a.order ?? Int.max
            let bo = b.order ?? Int.max
            if ao != bo { return ao < bo }
            return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
        }
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
        .sheet(item: $shareItem) { item in
            ActivityView(items: [item.url])
        }
        .sheet(isPresented: $showHistorySheet) {
            HistorySheet(
                history: store.history,
                onRestore: { saved in
                    level = saved.level
                    reportTitle = saved.reportTitle
                    reportDate = saved.reportDate
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
            HStack {
                Spacer()
                Text("Conditions")
                    .font(.system(size: 20, weight: .bold))
                Spacer()
            }
            .overlay(alignment: .trailing) {
                // This uses the system split view toggle already provided by NavigationSplitView
                // so it remains functional.
                EmptyView()
            }
            .padding(.horizontal)
            .padding(.top, 8)
            // Place the built-in split view sidebar toggle button at the top-right
            // (this will appear in the navigation bar area for the sidebar column)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        // no-op; actual toggle is provided by the system
                    } label: {
                        EmptyView()
                    }
                }
            }
            Picker("", selection: $level) {
                ForEach(TemplateLevel.allCases) { lvl in
                    Text(lvl.displayName).tag(lvl)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            // Category chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(TemplateCategory.allCases) { cat in
                        Button {
                            category = cat
                        } label: {
                            Text(cat.displayName)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(category == cat ? Color.primary : Color.secondary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule()
                                        .fill(category == cat ? Color.secondary.opacity(0.22) : Color.secondary.opacity(0.10))
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Category \(cat.displayName)")
                    }
                }
                .padding(.horizontal)
                .padding(.top, 2)
            }

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

            List(selection: $selectedTemplateID) {
                Section {
                    Button {
                        addOtherEntry()
                        selectedTemplateID = nil
                    } label: {
                        Label("Other", systemImage: "plus.circle")
                    }
                }

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
                                    TextField("Condition", text: $entry.title)
                                        .textFieldStyle(.plain)
                                        .font(.headline)
                                        .textInputAutocapitalization(.characters)
                                        .autocorrectionDisabled(true)

                                    Spacer()
                                    Menu {
                                        Button(PlanEntryStyle.clinical.menuTitle) {
                                            applyStyle(.clinical, to: &entry)
                                        }
                                        Button(PlanEntryStyle.education.menuTitle) {
                                            applyStyle(.education, to: &entry)
                                        }
                                    } label: {
                                        Image(systemName: entry.style == .clinical ? "stethoscope" : "info.circle")
                                            .foregroundStyle(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Section format")
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
                                        Text(entry.style.leftLabel)
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
                                        Text(entry.style.rightLabel)
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
                    Button("None") {
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
                        Text(store.selectedLetterheadName ?? "Letterhead")
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
        guard let t = store.template(id: templateID) else { return }
        if planEntries.contains(where: { $0.templateID == templateID }) { return }

        planEntries.append(
            PlanEntry(
                id: UUID(),
                templateID: templateID,
                title: t.title,
                originalTitle: t.title,
                style: t.defaultStyle,
                originalStyle: t.defaultStyle,
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
                originalTitle: "Other",
                style: .clinical,
                originalStyle: .clinical,
                assessment: "",
                plan: "",
                originalAssessment: "",
                originalPlan: ""
            )
        )
    }
    private func applyStyle(_ newStyle: PlanEntryStyle, to entry: inout PlanEntry) {
        guard entry.style != newStyle else { return }

        let trimmedTitle = entry.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseOriginal = entry.originalTitle.trimmingCharacters(in: .whitespacesAndNewlines)

        func stripAbout(_ s: String) -> String {
            if s.lowercased().hasPrefix("about ") {
                return String(s.dropFirst(6)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return s
        }

        switch (entry.style, newStyle) {
        case (.clinical, .education):
            if !trimmedTitle.lowercased().hasPrefix("about ") {
                let baseCurrent = stripAbout(trimmedTitle)
                let base = (stripAbout(trimmedTitle) == stripAbout(baseOriginal)) ? stripAbout(baseOriginal) : baseCurrent
                entry.title = base.isEmpty ? "About" : "About \(base)"
            }

        case (.education, .clinical):
            if trimmedTitle.lowercased().hasPrefix("about ") {
                let stripped = stripAbout(trimmedTitle)
                entry.title = stripped.isEmpty ? baseOriginal : stripped
            }

        default:
            break
        }

        entry.style = newStyle
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
        return entry.assessment != entry.originalAssessment
            || entry.plan != entry.originalPlan
            || entry.title != entry.originalTitle
            || entry.style != entry.originalStyle
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
        store.addToHistory(level: level, reportTitle: reportTitle, reportDate: reportDate, patientName: "", entries: planEntries)

        // Clear form fields.
        reportTitle = ""
        patientName = ""
        reportDate = Date()
        planEntries = []
        selectedTemplateID = nil
    }

    private func generateAndSharePDF() {
        do {
            let url = try PlanPDFBuilder.buildPDF(
                patientName: patientName,
                reportTitle: reportTitle,
                reportDate: reportDate,
                entries: planEntries,
                letterheadURL: store.selectedLetterheadName.map { store.letterheadURL(named: $0) }
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
    @State private var category: TemplateCategory = .general
    @State private var selectedID: UUID? = nil
    @State private var editMode: EditMode = .inactive
    @State private var pendingDeleteTemplateID: UUID? = nil
    @State private var showDeleteTemplateConfirm: Bool = false

    private var filtered: [ConditionTemplate] {
        let base = store.templates.filter { $0.level == level && (category == .general || $0.category == category) }
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)

        let list: [ConditionTemplate]
        if q.isEmpty {
            list = base.sorted { a, b in
                // Use ordering first; keep pinned grouped visually above non-pinned.
                if a.isPinned != b.isPinned { return a.isPinned && !b.isPinned }
                let ao = a.order ?? Int.max
                let bo = b.order ?? Int.max
                if ao != bo { return ao < bo }
                return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
            }
        } else {
            list = base.filter {
                $0.title.localizedCaseInsensitiveContains(q) ||
                $0.assessment.localizedCaseInsensitiveContains(q) ||
                $0.plan.localizedCaseInsensitiveContains(q)
            }
            .sorted { a, b in
                if a.isPinned != b.isPinned { return a.isPinned && !b.isPinned }
                let ao = a.order ?? Int.max
                let bo = b.order ?? Int.max
                if ao != bo { return ao < bo }
                return a.updatedAt > b.updatedAt
            }
        }
        return list
    }

    private var selectedTemplate: ConditionTemplate? {
        guard let id = selectedID else { return nil }
        return store.template(id: id)
    }

    var body: some View {
        NavigationSplitView {
            manageSidebar
        } detail: {
            manageDetail
        }
        .navigationTitle("Manage Templates")
        .alert("Delete template?", isPresented: $showDeleteTemplateConfirm) {
            Button("Delete", role: .destructive) {
                if let id = pendingDeleteTemplateID,
                   let idx = store.templates.firstIndex(where: { $0.id == id }) {
                    store.templates.remove(at: idx)
                    if selectedID == id { selectedID = nil }
                }
                pendingDeleteTemplateID = nil
            }
            Button("Cancel", role: .cancel) {
                pendingDeleteTemplateID = nil
            }
        } message: {
            Text("This will permanently delete the template.")
        }
    }

    private var manageSidebar: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                EditButton()
                    .font(.system(size: 16, weight: .semibold))

                Spacer()

                Text("Templates")
                    .font(.system(size: 20, weight: .bold))

                Spacer()

                Button {
                    createNewTemplate()
                } label: {
                    Label("New Template", systemImage: "plus")
                        .labelStyle(.iconOnly)
                        .font(.system(size: 18, weight: .semibold))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal)
            .padding(.top, 8)

            Picker("", selection: $level) {
                ForEach(TemplateLevel.allCases) { lvl in
                    Text(lvl.displayName).tag(lvl)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            // Category chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(TemplateCategory.allCases) { cat in
                        Button {
                            category = cat
                        } label: {
                            Text(cat.displayName)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(category == cat ? Color.primary : Color.secondary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule()
                                        .fill(category == cat ? Color.secondary.opacity(0.22) : Color.secondary.opacity(0.10))
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Category \(cat.displayName)")
                    }
                }
                .padding(.horizontal)
                .padding(.top, 2)
            }

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

            List(selection: $selectedID) {
                if filtered.isEmpty {
                    ContentUnavailableView(
                        "No templates",
                        systemImage: "doc.text",
                        description: Text("Tap + to add a template.")
                    )
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(filtered) { t in
                        HStack(spacing: 10) {
                            if editMode == .active {
                                Button {
                                    store.toggleVisible(id: t.id)
                                } label: {
                                    Image(systemName: t.isVisible ? "eye" : "eye.slash")
                                        .foregroundStyle(t.isVisible ? Color.secondary : Color.secondary.opacity(0.6))
                                }
                                .buttonStyle(.plain)

                                Button {
                                    store.togglePinned(id: t.id)
                                } label: {
                                    Image(systemName: t.isPinned ? "pin.fill" : "pin")
                                        .foregroundStyle(t.isPinned ? .yellow : .secondary)
                                }
                                .buttonStyle(.plain)
                            }

                            Text(t.title)
                                .font(.subheadline)
                                .lineLimit(2)

                            Spacer()

                            if editMode == .active {
                                Button {
                                    pendingDeleteTemplateID = t.id
                                    showDeleteTemplateConfirm = true
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundStyle(.red)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { selectedID = t.id }
                    }
                    .onMove { from, to in
                        guard editMode == .active else { return }

                        // Only allow reordering when not searching.
                        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard q.isEmpty else { return }

                        var ids = filtered.map { $0.id }
                        ids.move(fromOffsets: from, toOffset: to)
                        store.applyReorder(level: level, orderedIDs: ids)
                    }
                }
            }
        }
        .environment(\.editMode, $editMode)
    }

    private var manageDetail: some View {
        Group {
            if let t = selectedTemplate {
                ManageTemplateDetail(template: t, currentLevel: $level)
            } else {
                ContentUnavailableView(
                    "Select a template",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("Choose a template from the left to edit it.")
                )
            }
        }
    }

    private func createNewTemplate() {
        let new = ConditionTemplate(
            title: "New Condition",
            assessment: "",
            plan: "",
            level: level,
            category: category,
            defaultStyle: .clinical,
            isPinned: false,
            isVisible: true,
            order: store.nextOrderValue(for: level),
            createdAt: Date(),
            updatedAt: Date()
        )
        store.addTemplate(new)
        selectedID = new.id
    }
}
private struct ManageTemplateDetail: View {
    @EnvironmentObject private var store: AppStore

    let template: ConditionTemplate
    @Binding var currentLevel: TemplateLevel

    @State private var title: String = ""
    @State private var assessment: String = ""
    @State private var plan: String = ""
    @State private var level: TemplateLevel = .basic
    @State private var category: TemplateCategory = .general

    @State private var didLoad = false

    @State private var isEditing: Bool = false

    @State private var originalTitle: String = ""
    @State private var originalAssessment: String = ""
    @State private var originalPlan: String = ""
    @State private var originalLevel: TemplateLevel = .basic
    @State private var originalCategory: TemplateCategory = .general
    @State private var defaultStyle: PlanEntryStyle = .clinical
    @State private var originalDefaultStyle: PlanEntryStyle = .clinical

    private var leftFieldLabel: String {
        defaultStyle == .clinical ? "Default Assessment" : "Default Overview"
    }

    private var rightFieldLabel: String {
        defaultStyle == .clinical ? "Default Plan" : "Default Treatment Options"
    }

    private func stripAboutPrefix(_ s: String) -> String {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("about ") {
            return String(trimmed.dropFirst(6)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return trimmed
    }

    private func applyAboutTitleIfNeeded(old: PlanEntryStyle, new: PlanEntryStyle) {
        // Only auto-adjust the title while actively editing.
        guard isEditing else { return }

        let currentTrimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)

        switch (old, new) {
        case (.clinical, .education):
            // If switching to Education, prepend "About" unless already present.
            if !currentTrimmed.lowercased().hasPrefix("about ") {
                let base = stripAboutPrefix(currentTrimmed)
                title = base.isEmpty ? "About" : "About \(base)"
            }

        case (.education, .clinical):
            // If switching back to Clinical, remove the "About" prefix if present.
            if currentTrimmed.lowercased().hasPrefix("about ") {
                let base = stripAboutPrefix(currentTrimmed)
                title = base.isEmpty ? originalTitle : base
            }

        default:
            break
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                TextField("Condition name", text: $title)
                    .textFieldStyle(.roundedBorder)
                    .font(.title3)
                    .disabled(!isEditing)

                Spacer()

                if isEditing {
                    Button("Done") {
                        commitEdits()
                        isEditing = false
                    }
                    .buttonStyle(.bordered)

                    Button("Cancel") {
                        discardEdits()
                        isEditing = false
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button("Edit") {
                        beginEditing()
                        isEditing = true
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)

            HStack {
                Text("Level")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("Level", selection: $level) {
                    ForEach(TemplateLevel.allCases) { lvl in
                        Text(lvl.displayName).tag(lvl)
                    }
                }
                .disabled(!isEditing)
                .pickerStyle(.segmented)
                .frame(maxWidth: 360)
            }
            .padding(.horizontal)
            HStack {
                Text("Category")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("Category", selection: $category) {
                    ForEach(TemplateCategory.allCases) { cat in
                        Text(cat.displayName).tag(cat)
                    }
                }
                .disabled(!isEditing)
                .pickerStyle(.menu)
            }
            .padding(.horizontal)
            HStack {
                Text("Default Format")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer()

                Menu {
                    Button(PlanEntryStyle.clinical.menuTitle) {
                        defaultStyle = .clinical
                    }

                    Button(PlanEntryStyle.education.menuTitle) {
                        defaultStyle = .education
                    }
                } label: {
                    Image(systemName: defaultStyle == .clinical ? "stethoscope" : "info.circle")
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.secondary.opacity(0.12))
                        )
                }
                .buttonStyle(.plain)
                .disabled(!isEditing)
                .accessibilityLabel("Default format")
                .onChange(of: defaultStyle) { oldValue, newValue in
                    applyAboutTitleIfNeeded(old: oldValue, new: newValue)
                }
            }
            .padding(.horizontal)

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(leftFieldLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $assessment)
                        .disabled(!isEditing)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(.secondary.opacity(0.35))
                        )
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(rightFieldLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $plan)
                        .disabled(!isEditing)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(.secondary.opacity(0.35))
                        )
                }
            }
            .padding(.horizontal)

            Spacer()
        }
        .onAppear {
            loadIfNeeded()
            isEditing = false
        }
        .onChange(of: template.id) { _, _ in
            didLoad = false
            isEditing = false
            loadIfNeeded()
        }
        .onChange(of: level) { _, _ in
            currentLevel = level
        }
    }

    private func loadIfNeeded() {
        guard !didLoad else { return }
        didLoad = true

        title = template.title
        assessment = template.assessment
        plan = template.plan
        level = template.level
        category = template.category
        originalCategory = template.category
        currentLevel = template.level
        defaultStyle = template.defaultStyle
        originalDefaultStyle = template.defaultStyle

        // Capture originals so Cancel can revert.
        originalTitle = template.title
        originalAssessment = template.assessment
        originalPlan = template.plan
        originalLevel = template.level
    }

    private func beginEditing() {
        // Refresh originals from the current stored version.
        guard let t = store.template(id: template.id) else { return }
        originalTitle = t.title
        originalAssessment = t.assessment
        originalPlan = t.plan
        originalLevel = t.level
        originalCategory = t.category
        defaultStyle = t.defaultStyle
        originalDefaultStyle = t.defaultStyle

        title = t.title
        assessment = t.assessment
        plan = t.plan
        level = t.level
        category = t.category
        currentLevel = t.level
    }

    private func discardEdits() {
        title = originalTitle
        assessment = originalAssessment
        plan = originalPlan
        level = originalLevel
        currentLevel = originalLevel
        defaultStyle = originalDefaultStyle
        category = originalCategory
    }

    private func commitEdits() {
        guard didLoad else { return }
        guard var t = store.template(id: template.id) else { return }

        let previousLevel = t.level
        t.title = title
        t.assessment = assessment
        t.plan = plan
        t.defaultStyle = defaultStyle
        t.category = category

        if previousLevel != level {
            t.level = level
            t.order = store.nextOrderValue(for: level)
        }

        t.updatedAt = Date()
        store.updateTemplate(t)

        // Update originals after saving.
        originalTitle = t.title
        originalAssessment = t.assessment
        originalPlan = t.plan
        originalLevel = t.level
        currentLevel = t.level
        originalDefaultStyle = t.defaultStyle
        originalCategory = t.category
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
    @State private var category: TemplateCategory = .general
    @State private var isPinned: Bool = false
    @State private var isVisible: Bool = true

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

                Section("Category") {
                    Picker("", selection: $category) {
                        ForEach(TemplateCategory.allCases) { cat in
                            Text(cat.displayName).tag(cat)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section {
                    Toggle("Visible in New Plan", isOn: $isVisible)
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
                self.category = .general
                self.isPinned = false
                self.isVisible = true
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
            category = t.category
            isPinned = t.isPinned
            isVisible = t.isVisible
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
                category: category,
                isPinned: isPinned,
                isVisible: isVisible,
                order: store.nextOrderValue(for: level),
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
            existing.category = category
            existing.isPinned = isPinned
            existing.isVisible = isVisible
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

    @State private var showImportTemplatesSheet = false
    @State private var importMerge = true

    @State private var showLetterheadImporter = false
    @State private var showFactoryResetConfirm = false

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
                    showImportTemplatesSheet = true
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

            Section {
                Button(role: .destructive) {
                    showFactoryResetConfirm = true
                } label: {
                    Label("Reset to Factory Defaults", systemImage: "arrow.counterclockwise")
                }
            } footer: {
                Text("This will delete all custom templates, clear history, and remove any imported letterhead PDFs.")
            }
        }
        .navigationTitle("Settings")
        .alert("Reset to Factory Defaults?", isPresented: $showFactoryResetConfirm) {
            Button("Reset", role: .destructive) {
                store.resetToFactoryDefaults()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove all custom templates, clear history, and delete imported letterhead PDFs. This cannot be undone.")
        }
        .fileExporter(
            isPresented: $showExport,
            document: exportDoc,
            contentType: .json,
            defaultFilename: "SummaryTemplates"
        ) { _ in }
        .sheet(isPresented: $showImportTemplatesSheet) {
            JSONDocumentPicker(
                onPick: { url in
                    do {
                        let started = url.startAccessingSecurityScopedResource()
                        defer { if started { url.stopAccessingSecurityScopedResource() } }
                        let data = try Data(contentsOf: url)
                        try store.importTemplatesJSON(data, merge: importMerge)
                    } catch {
                        // ignore
                    }
                },
                onCancel: {
                    // no-op
                }
            )
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

// MARK: - JSONDocumentPicker

private struct JSONDocumentPicker: UIViewControllerRepresentable {
    let onPick: (URL) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick, onCancel: onCancel)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [UTType.json], asCopy: true)
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void
        let onCancel: () -> Void

        init(onPick: @escaping (URL) -> Void, onCancel: @escaping () -> Void) {
            self.onPick = onPick
            self.onCancel = onCancel
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            onPick(url)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onCancel()
        }
    }
}

// MARK: - PDF generation

enum PlanPDFBuilder {
    static func buildPDF(patientName: String, reportTitle: String, reportDate: Date, entries: [PlanEntry], letterheadURL: URL?) throws -> URL {
        let filenamePatient = patientName.trimmingCharacters(in: .whitespacesAndNewlines)
        let safeName = filenamePatient.isEmpty ? "Patient" : filenamePatient
        let outURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("TxPlan_\(safeName)_\(Int(Date().timeIntervalSince1970)).pdf")

        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792) // US Letter @ 72 dpi
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)

        let data = renderer.pdfData { ctx in
            let marginX: CGFloat = 54
            let contentWidth = pageRect.width - 2 * marginX
            let contentTopY: CGFloat = 112
            let footerY: CGFloat = pageRect.height - 78
            let pageBreakThreshold: CGFloat = pageRect.height - 110

            // Shared measurement/drawing helpers
            func normalize(_ s: String) -> String {
                // Convert escaped newlines/tabs stored in templates into actual characters.
                s.replacingOccurrences(of: "\\r\\n", with: "\n")
                    .replacingOccurrences(of: "\\n", with: "\n")
                    .replacingOccurrences(of: "\\t", with: "\t")
            }

            // Attributed string helpers supporting bullets
            func makeAttributed(_ text: String, font: UIFont, alignment: NSTextAlignment, bullets: Bool) -> NSAttributedString {
                let para = NSMutableParagraphStyle()
                para.alignment = alignment
                para.lineBreakMode = .byWordWrapping

                if bullets {
                    // Convert simple bullet markers at line starts into typographic bullets.
                    // Supports: "- ", "* ", and "• "
                    let lines = text.components(separatedBy: "\n")
                    let convertedLines = lines.map { line -> String in
                        if line.hasPrefix("- ") {
                            return "•\t" + String(line.dropFirst(2))
                        }
                        if line.hasPrefix("* ") {
                            return "•\t" + String(line.dropFirst(2))
                        }
                        if line.hasPrefix("• ") {
                            return "•\t" + String(line.dropFirst(2))
                        }
                        return line
                    }

                    let converted = convertedLines.joined(separator: "\n")

                    let containsBullet = converted.contains("•\t")

                    if containsBullet {
                        // Apply hanging indent only when actual bullets are present
                        para.defaultTabInterval = 14
                        para.tabStops = [NSTextTab(textAlignment: .left, location: 14, options: [:])]
                        para.firstLineHeadIndent = 0
                        para.headIndent = 14
                    } else {
                        // No bullets → normal paragraph wrapping
                        para.firstLineHeadIndent = 0
                        para.headIndent = 0
                    }

                    return NSAttributedString(
                        string: converted,
                        attributes: [
                            .font: font,
                            .paragraphStyle: para
                        ]
                    )
                } else {
                    return NSAttributedString(
                        string: text,
                        attributes: [
                            .font: font,
                            .paragraphStyle: para
                        ]
                    )
                }
            }

            func attributedHeight(_ attr: NSAttributedString, width: CGFloat) -> CGFloat {
                let rect = attr.boundingRect(
                    with: CGSize(width: width, height: 10_000),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    context: nil
                )
                return ceil(rect.height)
            }

            func drawAttributed(_ attr: NSAttributedString, x: CGFloat, y: CGFloat, width: CGFloat) -> CGFloat {
                let h = attributedHeight(attr, width: width)
                attr.draw(with: CGRect(x: x, y: y, width: width, height: h), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
                return y + h
            }

            // Build pages by estimating block heights (two-pass so we know total page count)
            struct Block {
                enum Kind {
                    case docTitle
                    case patientDateRow
                    case condTitleBox
                    case label
                    case body
                }
                let kind: Kind
                let leftText: String
                let rightText: String? // used only for patientDateRow
                let font: UIFont
                let topPad: CGFloat
                let bottomPad: CGFloat
                let keepWithNext: Int
            }

            var blocks: [Block] = []

            let trimmedTitle = reportTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedTitle.isEmpty {
                blocks.append(
                    Block(
                        kind: .docTitle,
                        leftText: normalize(trimmedTitle),
                        rightText: nil,
                        font: .boldSystemFont(ofSize: 17),
                        topPad: 0,
                        bottomPad: 8,
                        keepWithNext: 1
                    )
                )
            }

            let trimmedPatient = patientName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedPatient.isEmpty {
                let patientLeft = "Patient: \(trimmedPatient)"
                let dateRight = "Date of Exam: \(reportDate.formatted(date: .abbreviated, time: .omitted))"
                blocks.append(
                    Block(
                        kind: .patientDateRow,
                        leftText: normalize(patientLeft),
                        rightText: normalize(dateRight),
                        font: .systemFont(ofSize: 12),
                        topPad: 0,
                        bottomPad: 14,
                        keepWithNext: 1
                    )
                )
            }

            for e in entries {
                blocks.append(
                    Block(
                        kind: .condTitleBox,
                        leftText: normalize(e.title).uppercased(),
                        rightText: nil,
                        font: .boldSystemFont(ofSize: 10),
                        topPad: 0,
                        bottomPad: 10,
                        keepWithNext: 2
                    )
                )

                let a = e.assessment.trimmingCharacters(in: .whitespacesAndNewlines)
                if !a.isEmpty {
                    blocks.append(
                        Block(
                            kind: .label,
                            leftText: normalize("\(e.style.leftLabel):"),
                            rightText: nil,
                            font: .boldSystemFont(ofSize: 11),
                            topPad: 0,
                            bottomPad: 2,
                            keepWithNext: 1
                        )
                    )
                    blocks.append(
                        Block(
                            kind: .body,
                            leftText: normalize(a),
                            rightText: nil,
                            font: .systemFont(ofSize: 10),
                            topPad: 0,
                            bottomPad: 8,
                            keepWithNext: 0
                        )
                    )
                }

                let p = e.plan.trimmingCharacters(in: .whitespacesAndNewlines)
                if !p.isEmpty {
                    blocks.append(
                        Block(
                            kind: .label,
                            leftText: normalize("\(e.style.rightLabel):"),
                            rightText: nil,
                            font: .boldSystemFont(ofSize: 11),
                            topPad: 0,
                            bottomPad: 2,
                            keepWithNext: 1
                        )
                    )
                    blocks.append(
                        Block(
                            kind: .body,
                            leftText: normalize(p),
                            rightText: nil,
                            font: .systemFont(ofSize: 10),
                            topPad: 0,
                            bottomPad: 14,
                            keepWithNext: 0
                        )
                    )
                }
                // (Divider removed)
            }

            // Paginate
            var pages: [[Block]] = [[]]
            var y: CGFloat = contentTopY

            func startNewPage() {
                pages.append([])
                y = contentTopY
            }

            let halfWidth = (contentWidth - 12) / 2

            func blockHeight(_ b: Block) -> CGFloat {
                switch b.kind {
                case .patientDateRow:
                    let leftAttr = makeAttributed(b.leftText, font: b.font, alignment: .left, bullets: false)
                    let rightAttr = makeAttributed(b.rightText ?? "", font: b.font, alignment: .right, bullets: false)
                    let leftH = attributedHeight(leftAttr, width: halfWidth)
                    let rightH = attributedHeight(rightAttr, width: halfWidth)
                    return b.topPad + max(leftH, rightH) + b.bottomPad

                case .condTitleBox:
                    let outdent: CGFloat = 8
                    let innerPadY: CGFloat = 6
                    let innerPadX: CGFloat = 9
                    let titleAttr = makeAttributed(b.leftText, font: b.font, alignment: .left, bullets: false)
                    let h = attributedHeight(titleAttr, width: (contentWidth + outdent) - innerPadX * 2)
                    return b.topPad + (h + innerPadY * 2) + b.bottomPad

                case .docTitle:
                    let attr = makeAttributed(b.leftText, font: b.font, alignment: .center, bullets: false)
                    return b.topPad + attributedHeight(attr, width: contentWidth) + b.bottomPad

                case .label:
                    let indent: CGFloat = 14
                    let attr = makeAttributed(b.leftText, font: b.font, alignment: .left, bullets: false)
                    return b.topPad + attributedHeight(attr, width: contentWidth - indent) + b.bottomPad

                case .body:
                    let indent: CGFloat = 18
                    let attr = makeAttributed(b.leftText, font: b.font, alignment: .left, bullets: true)
                    return b.topPad + attributedHeight(attr, width: contentWidth - indent) + b.bottomPad
                }
            }

            var i = 0
            while i < blocks.count {
                let b = blocks[i]

                // If this block requests to stay with the next N blocks, measure them together.
                var combinedH = blockHeight(b)
                if b.keepWithNext > 0 {
                    let end = min(blocks.count - 1, i + b.keepWithNext)
                    if i < end {
                        for j in (i + 1)...end {
                            combinedH += blockHeight(blocks[j])
                        }
                    }
                }

                // If the combined group would overflow, start a new page BEFORE the group.
                if y + combinedH > pageBreakThreshold, !pages[pages.count - 1].isEmpty {
                    startNewPage()
                }

                // Add current block.
                let h = blockHeight(b)
                pages[pages.count - 1].append(b)
                y += h
                i += 1
            }

            let totalPages = pages.count

            // Render pages
            for (pageIndex, pageBlocks) in pages.enumerated() {
                ctx.beginPage()

                // Background letterhead, if provided
                if let bgURL = letterheadURL,
                   let doc = PDFDocument(url: bgURL),
                   let page = doc.page(at: 0) {
                    // PDF pages use a bottom-left origin; UIGraphicsPDFRenderer uses top-left.
                    // Flip only while drawing the background so it stays upright.
                    ctx.cgContext.saveGState()
                    ctx.cgContext.translateBy(x: 0, y: pageRect.height)
                    ctx.cgContext.scaleBy(x: 1, y: -1)
                    page.draw(with: .mediaBox, to: ctx.cgContext)
                    ctx.cgContext.restoreGState()
                }

                var yCursor: CGFloat = contentTopY
                let halfWidth = (contentWidth - 12) / 2

                for b in pageBlocks {
                    yCursor += b.topPad

                    switch b.kind {
                    case .docTitle:
                        let attr = makeAttributed(b.leftText, font: b.font, alignment: .center, bullets: false)
                        yCursor = drawAttributed(attr, x: marginX, y: yCursor, width: contentWidth)

                    case .patientDateRow:
                        let leftAttr = makeAttributed(b.leftText, font: b.font, alignment: .left, bullets: false)
                        let rightAttr = makeAttributed(b.rightText ?? "", font: b.font, alignment: .right, bullets: false)
                        _ = drawAttributed(leftAttr, x: marginX, y: yCursor, width: halfWidth)
                        _ = drawAttributed(rightAttr, x: marginX + halfWidth + 12, y: yCursor, width: halfWidth)
                        let leftH = attributedHeight(leftAttr, width: halfWidth)
                        let rightH = attributedHeight(rightAttr, width: halfWidth)
                        yCursor += max(leftH, rightH)

                    case .condTitleBox:
                        // Slightly outdent the header box for emphasis
                        let outdent: CGFloat = 8
                        let innerPadX: CGFloat = 9
                        let innerPadY: CGFloat = 6
                        let titleAttr = makeAttributed(b.leftText, font: b.font, alignment: .left, bullets: false)
                        let titleH = attributedHeight(titleAttr, width: (contentWidth + outdent) - innerPadX * 2)
                        let boxH = titleH + innerPadY * 2
                        let boxRect = CGRect(x: marginX - outdent, y: yCursor, width: contentWidth + outdent, height: boxH)
                        ctx.cgContext.saveGState()
                        ctx.cgContext.setLineWidth(2.5)
                        ctx.cgContext.setStrokeColor(UIColor.black.cgColor)
                        let path = UIBezierPath(roundedRect: boxRect, cornerRadius: 8)
                        ctx.cgContext.addPath(path.cgPath)
                        ctx.cgContext.strokePath()
                        ctx.cgContext.restoreGState()

                        _ = drawAttributed(titleAttr, x: (marginX - outdent) + innerPadX, y: yCursor + innerPadY, width: (contentWidth + outdent) - innerPadX * 2)
                        yCursor += boxH

                    case .label:
                        let indent: CGFloat = 14
                        let attr = makeAttributed(b.leftText, font: b.font, alignment: .left, bullets: false)
                        yCursor = drawAttributed(attr, x: marginX + indent, y: yCursor, width: contentWidth - indent)

                    case .body:
                        let indent: CGFloat = 18
                        let attr = makeAttributed(b.leftText, font: b.font, alignment: .left, bullets: true)
                        yCursor = drawAttributed(attr, x: marginX + indent, y: yCursor, width: contentWidth - indent)
                    }

                    yCursor += b.bottomPad
                }

                // Footer page numbering (bottom-right)
                let footerText = "Page \(pageIndex + 1) of \(totalPages)"
                let footerFont = UIFont.systemFont(ofSize: 10)
                let footerAttr = makeAttributed(footerText, font: footerFont, alignment: .right, bullets: false)
                _ = drawAttributed(footerAttr, x: marginX, y: footerY, width: contentWidth)
            }
        }

        try data.write(to: outURL, options: [.atomic])
        return outURL
    }
}


private struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
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
