import SwiftUI
import Combine
import Foundation

// MARK: - Shared model types

typealias EntryCategory = String

extension EntryCategory {
    static let general: EntryCategory = "general"
}


struct CategoryItem: Identifiable, Codable, Equatable {
    var id: String
    var name: String
    var order: Int
}

enum LibrarySortMode: String, Codable, CaseIterable {
    case manual
    case alphabeticalAZ
    case alphabeticalZA
    case newestUpdated
    case oldestUpdated
}

struct LibraryCollection: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var entries: [LibraryEntry]
    var sortMode: LibrarySortMode = .manual
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
}

struct LibrariesState: Codable, Equatable {
    var libraries: [LibraryCollection]
    var activeLibraryID: UUID?
}

enum LegacyTemplateLevel: String, Codable {
    case basic
    case advanced
}

struct LibraryEntry: Identifiable, Codable, Equatable {
    var id: UUID = UUID()

    var title: String
    var body: String
    var bodyRTFData: Data? = nil

    var category: EntryCategory = .general
    var isFavorite: Bool
    /// If false, the entry is hidden from the New Report picker but remains available in Library.
    var isVisible: Bool = true
    /// Controls display ordering (lower first). Optional for backward compatibility.
    var order: Int? = nil

    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var lastImportedAt: Date? = nil

    enum CodingKeys: String, CodingKey {
        case id, title, body, bodyRTFData, assessment, plan, category, defaultStyle, isFavorite, isPinned, isVisible, order, createdAt, updatedAt, lastImportedAt, level
    }

    init(
        id: UUID = UUID(),
        title: String,
        body: String,
        bodyRTFData: Data? = nil,
        category: EntryCategory = .general,
        isFavorite: Bool,
        isVisible: Bool = true,
        order: Int? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        lastImportedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.bodyRTFData = bodyRTFData
        self.category = category
        self.isFavorite = isFavorite
        self.isVisible = isVisible
        self.order = order
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastImportedAt = lastImportedAt
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

        self.bodyRTFData = try c.decodeIfPresent(Data.self, forKey: .bodyRTFData)

        _ = try? c.decode(LegacyTemplateLevel.self, forKey: .level)
        self.category = (try? c.decode(EntryCategory.self, forKey: .category)) ?? .general
        _ = try? c.decode(String.self, forKey: .defaultStyle)
        self.isFavorite = try c.decodeIfPresent(Bool.self, forKey: .isFavorite)
            ?? (try c.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false)
        self.isVisible = try c.decodeIfPresent(Bool.self, forKey: .isVisible) ?? true
        self.order = try c.decodeIfPresent(Int.self, forKey: .order)
        self.createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        self.updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
        self.lastImportedAt = try c.decodeIfPresent(Date.self, forKey: .lastImportedAt)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(body, forKey: .body)
        try c.encodeIfPresent(bodyRTFData, forKey: .bodyRTFData)
        try c.encode(category, forKey: .category)
        try c.encode(isFavorite, forKey: .isFavorite)
        try c.encode(isVisible, forKey: .isVisible)
        try c.encodeIfPresent(order, forKey: .order)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encodeIfPresent(lastImportedAt, forKey: .lastImportedAt)
    }
}

extension LibraryEntry {
    var attributedBody: NSAttributedString {
        if let bodyRTFData,
           let attributed = try? NSAttributedString.eyeBrary_fromRTFData(bodyRTFData) {
            return attributed
        }

        return NSAttributedString(string: body)
    }

    mutating func setAttributedBody(_ attributed: NSAttributedString) {
        body = attributed.string
        bodyRTFData = try? attributed.eyeBrary_toRTFData()
        updatedAt = Date()
    }
}

struct PlanEntry: Identifiable, Codable, Equatable {
    var id: UUID
    var templateID: UUID?   // nil for “Other”

    var title: String
    var originalTitle: String

    var body: String
    var originalBody: String
    var bodyRTFData: Data? = nil
    var originalBodyRTFData: Data? = nil

    init(
        id: UUID,
        templateID: UUID?,
        title: String,
        originalTitle: String,
        body: String,
        originalBody: String,
        bodyRTFData: Data? = nil,
        originalBodyRTFData: Data? = nil
    ) {
        self.id = id
        self.templateID = templateID
        self.title = title
        self.originalTitle = originalTitle
        self.body = body
        self.originalBody = originalBody
        self.bodyRTFData = bodyRTFData
        self.originalBodyRTFData = originalBodyRTFData
    }
}

extension PlanEntry {
    enum CodingKeys: String, CodingKey {
        case id, templateID, EntryID, title, originalTitle, body, originalBody, bodyRTFData, originalBodyRTFData, assessment, plan, originalAssessment, originalPlan
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
        bodyRTFData = try c.decodeIfPresent(Data.self, forKey: .bodyRTFData)
        originalBodyRTFData = try c.decodeIfPresent(Data.self, forKey: .originalBodyRTFData)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encodeIfPresent(templateID, forKey: .templateID)
        try c.encode(title, forKey: .title)
        try c.encode(originalTitle, forKey: .originalTitle)
        try c.encode(body, forKey: .body)
        try c.encode(originalBody, forKey: .originalBody)
        try c.encodeIfPresent(bodyRTFData, forKey: .bodyRTFData)
        try c.encodeIfPresent(originalBodyRTFData, forKey: .originalBodyRTFData)
    }
}

extension PlanEntry {
    var attributedBody: NSAttributedString {
        if let bodyRTFData,
           let attributed = try? NSAttributedString.eyeBrary_fromRTFData(bodyRTFData) {
            return attributed
        }
        return NSAttributedString(string: body)
    }

    var attributedOriginalBody: NSAttributedString {
        if let originalBodyRTFData,
           let attributed = try? NSAttributedString.eyeBrary_fromRTFData(originalBodyRTFData) {
            return attributed
        }
        return NSAttributedString(string: originalBody)
    }

    mutating func setAttributedBody(_ attributed: NSAttributedString) {
        body = attributed.string
        bodyRTFData = try? attributed.eyeBrary_toRTFData()
    }

    mutating func setAttributedOriginalBody(_ attributed: NSAttributedString) {
        originalBody = attributed.string
        originalBodyRTFData = try? attributed.eyeBrary_toRTFData()
    }
}

struct SavedPlan: Identifiable, Codable, Equatable {
    var id: UUID
    var patientName: String
    var reportTitle: String
    var reportDate: Date
    var entries: [PlanEntry]
    var createdAt: Date
    var updatedAt: Date
}

struct LetterheadState: Codable, Equatable {
    var letterheads: [String]
    var selectedLetterheadName: String?
}

struct SafeZoneConfig: Codable, Equatable {
    var safeZone: CGRect          // normalized 0...1, top-left origin
    var pageNumberOrigin: CGPoint // normalized 0...1, top-left of the page-number stamp
}

struct UndoSnapshot: Codable, Equatable {
    var libraries: [LibraryCollection]
    var activeLibraryID: UUID?
    var categories: [CategoryItem]
}

struct EyeBraryLibraryManifest: Codable, Equatable {
    var format: String
    var formatVersion: Int
    var libraryName: String
    var exportedAt: Date
    var entries: [EyeBraryLibraryManifestEntry]

    static let currentFormat = "eyebrarylib"
    static let currentFormatVersion = 1
}

struct EyeBraryLibraryManifestEntry: Codable, Equatable {
    var id: UUID
    var title: String
    var category: EntryCategory
    var isFavorite: Bool
    var isVisible: Bool
    var order: Int?
    var createdAt: Date
    var updatedAt: Date
    var lastImportedAt: Date?
    var contentFile: String
}

extension JSONEncoder {
    static var standard: JSONEncoder {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        return enc
    }

    static var pretty: JSONEncoder {
        let enc = JSONEncoder.standard
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return enc
    }
}

extension JSONDecoder {
    static var standard: JSONDecoder {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return dec
    }
}

@MainActor
final class AppStore: ObservableObject {
    @Published private(set) var canUndo: Bool = false
    @Published private(set) var canRedo: Bool = false
    // Libraries / Entries
    @Published var libraries: [LibraryCollection] = [] {
        didSet {
            guard !isSynchronizingLibraryState else {
                persistLibraries()
                return
            }

            if activeLibraryIndex == nil {
                activeLibraryID = libraries.first?.id
            }

            persistLibraries()
            syncEntriesFromActiveLibrary()
        }
    }

    @Published var activeLibraryID: UUID? = nil {
        didSet {
            guard !isSynchronizingLibraryState else { return }
            persistLibraries()
            syncEntriesFromActiveLibrary()
        }
    }

    @Published var entries: [LibraryEntry] = [] {
        didSet {
            guard !isSynchronizingLibraryState else { return }
            syncActiveLibraryFromEntries()
        }
    }

    @Published var categories: [CategoryItem] = [] {
        didSet { persistCategories() }
    }

    @Published var plans: [SavedPlan] = [] {
        didSet { persistPlans() }
    }

    @Published var letterheads: [String] = [] {
        didSet { persistLetterheads() }
    }

    @Published var selectedLetterheadName: String? = nil {
        didSet { persistLetterheads() }
    }

    @Published var safeZoneConfigs: [String: SafeZoneConfig] = [:] {
        didSet { persistSafeZoneConfigs() }
    }

    var history: [SavedPlan] {
        get { plans }
        set { plans = newValue }
    }

    private let librariesKey = "EYEbrary.libraries.v1"
    private let templatesKey = "EYEbrary.conditionTemplates.v1"
    private let categoriesKey = "EYEbrary.categories.v1"
    private let plansKey = "EYEbrary.savedPlans.v1"
    private let letterheadsKey = "EYEbrary.letterheads.v1"
    private let safeZoneConfigsKey = "EYEbrary.safeZoneConfigs.v1"
    private let launchAcknowledgementKey = "EYEbrary.hasAcknowledgedAppInformation.v1"
    private let bundledDefaultLibraryName = "Default Library"
    private let bundledDefaultLibraryExtension = "eyebrarylib"
    private let normalizeTextOnImportKey = "EYEbrary.normalizeTextOnImport.v1"
    private let reportFontSizeKey = "EYEbrary.reportFontSize.v1"

    private var isSynchronizingLibraryState = false
    private var undoStack: [UndoSnapshot] = []
    private var redoStack: [UndoSnapshot] = []
    private var isRestoringUndoSnapshot = false
    private let maxUndoSnapshots = 50

    private var shouldNormalizeTextOnImport: Bool {
        if UserDefaults.standard.object(forKey: normalizeTextOnImportKey) == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: normalizeTextOnImportKey)
    }

    /// Body font size (points) for generated report PDFs. 10 is the historical
    /// default; larger sizes are offered for patients with low vision.
    var reportFontSize: Double {
        get {
            let stored = UserDefaults.standard.double(forKey: reportFontSizeKey)
            return stored == 0 ? 10 : stored
        }
        set {
            objectWillChange.send()
            UserDefaults.standard.set(newValue, forKey: reportFontSizeKey)
        }
    }
    
    init() {
        loadCategories()
        loadLibraries()
        loadPlans()
        loadLetterheads()
        loadSafeZoneConfigs()
        if categories.isEmpty { seedDefaultCategories() }
        if libraries.isEmpty { seedDefaults() }
        ensureAtLeastOneLibraryExists()
        ensureTemplateOrdering()
        syncEntriesFromActiveLibrary()
    }

    // MARK: - Undo / Redo

    private func makeUndoSnapshot() -> UndoSnapshot {
        UndoSnapshot(
            libraries: libraries,
            activeLibraryID: activeLibraryID,
            categories: categories
        )
    }

    private func updateUndoAvailability() {
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
    }

    func pushUndoSnapshot() {
        guard !isRestoringUndoSnapshot else { return }
        undoStack.append(makeUndoSnapshot())
        if undoStack.count > maxUndoSnapshots {
            undoStack.removeFirst(undoStack.count - maxUndoSnapshots)
        }
        redoStack.removeAll()
        updateUndoAvailability()
    }

    private func restoreUndoSnapshot(_ snapshot: UndoSnapshot) {
        isRestoringUndoSnapshot = true
        libraries = snapshot.libraries
        activeLibraryID = snapshot.activeLibraryID
        categories = snapshot.categories
        isRestoringUndoSnapshot = false
        ensureAtLeastOneLibraryExists()
        ensureTemplateOrdering()
        syncEntriesFromActiveLibrary()
        updateUndoAvailability()
    }

    func undo() {
        guard let snapshot = undoStack.popLast() else {
            updateUndoAvailability()
            return
        }
        redoStack.append(makeUndoSnapshot())
        restoreUndoSnapshot(snapshot)
    }

    func redo() {
        guard let snapshot = redoStack.popLast() else {
            updateUndoAvailability()
            return
        }
        undoStack.append(makeUndoSnapshot())
        restoreUndoSnapshot(snapshot)
    }

    // MARK: - Active Library

    var activeLibrary: LibraryCollection? {
        guard let index = activeLibraryIndex else { return nil }
        return libraries[index]
    }

    var activeLibraryName: String {
        activeLibrary?.name ?? bundledDefaultLibraryName
    }

    private var activeLibraryIndex: Int? {
        if let activeLibraryID,
           let index = libraries.firstIndex(where: { $0.id == activeLibraryID }) {
            return index
        }
        return libraries.isEmpty ? nil : 0
    }

    func sortedLibraries() -> [LibraryCollection] {
        libraries
    }

    func setActiveLibrary(id: UUID) {
        guard libraries.contains(where: { $0.id == id }) else { return }
        activeLibraryID = id
    }

    @discardableResult
    func createLibrary(named rawName: String) -> UUID? {
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        pushUndoSnapshot()
        let newLibrary = LibraryCollection(
            name: trimmed,
            entries: [],
            sortMode: .manual,
            createdAt: Date(),
            updatedAt: Date()
        )
        libraries.append(newLibrary)
        activeLibraryID = newLibrary.id
        return newLibrary.id
    }

    func renameLibrary(id: UUID, to rawName: String) {
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let index = libraries.firstIndex(where: { $0.id == id }) else { return }

        pushUndoSnapshot()
        libraries[index].name = trimmed
        libraries[index].updatedAt = Date()
    }

    func deleteLibrary(id: UUID) {
        guard !libraries.isEmpty else { return }
        guard let index = libraries.firstIndex(where: { $0.id == id }) else { return }

        pushUndoSnapshot()
        if libraries.count == 1 {
            let replacement = makeDefaultLibrary(name: bundledDefaultLibraryName, entries: [])
            libraries = [replacement]
            activeLibraryID = replacement.id
            return
        }

        libraries.remove(at: index)

        if activeLibraryID == id {
            activeLibraryID = libraries.first?.id
        }
    }

    func sortMode(for libraryID: UUID? = nil) -> LibrarySortMode {
        let targetID = libraryID ?? activeLibraryID
        guard let targetID,
              let index = libraries.firstIndex(where: { $0.id == targetID }) else {
            return .manual
        }
        return libraries[index].sortMode
    }

    func setSortMode(_ mode: LibrarySortMode, for libraryID: UUID? = nil) {
        let targetID = libraryID ?? activeLibraryID
        guard let targetID,
              let index = libraries.firstIndex(where: { $0.id == targetID }) else { return }

        libraries[index].sortMode = mode
        libraries[index].updatedAt = Date()
    }

    private func ensureAtLeastOneLibraryExists() {
        guard libraries.isEmpty else {
            if activeLibraryIndex == nil {
                activeLibraryID = libraries.first?.id
            }
            return
        }

        let library = makeDefaultLibrary(
            name: bundledDefaultLibraryName,
            entries: loadBundledDefaultLibraryIfAvailable() ?? factoryDefaultTemplates()
        )
        libraries = [library]
        activeLibraryID = library.id
    }

    private func syncEntriesFromActiveLibrary() {
        guard !isSynchronizingLibraryState else { return }
        isSynchronizingLibraryState = true
        entries = activeLibrary?.entries ?? []
        isSynchronizingLibraryState = false
    }

    private func syncActiveLibraryFromEntries() {
        guard !isSynchronizingLibraryState else { return }
        guard let index = activeLibraryIndex else { return }

        isSynchronizingLibraryState = true
        libraries[index].entries = entries
        libraries[index].updatedAt = Date()
        isSynchronizingLibraryState = false
    }

    private func makeDefaultLibrary(name: String, entries: [LibraryEntry]) -> LibraryCollection {
        LibraryCollection(
            name: name,
            entries: entries,
            sortMode: .manual,
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    // MARK: - Ordering

    private func ensureTemplateOrdering() {
        guard !libraries.isEmpty else { return }

        var updatedLibraries = libraries
        var didChange = false

        for libraryIndex in updatedLibraries.indices {
            if updatedLibraries[libraryIndex].entries.allSatisfy({ $0.order != nil }) {
                continue
            }

            let sorted = updatedLibraries[libraryIndex].entries.sorted { a, b in
                if a.isFavorite != b.isFavorite { return a.isFavorite && !b.isFavorite }
                let ao = a.order ?? Int.max
                let bo = b.order ?? Int.max
                if ao != bo { return ao < bo }
                return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
            }

            for (idx, entry) in sorted.enumerated() {
                if let entryIndex = updatedLibraries[libraryIndex].entries.firstIndex(where: { $0.id == entry.id }),
                   updatedLibraries[libraryIndex].entries[entryIndex].order == nil {
                    updatedLibraries[libraryIndex].entries[entryIndex].order = idx
                    didChange = true
                }
            }
        }

        if didChange {
            libraries = updatedLibraries
        } else {
            syncEntriesFromActiveLibrary()
        }
    }

    func applyTemplateOrder(_ orderedIDs: [UUID]) {
        pushUndoSnapshot()
        for (i, id) in orderedIDs.enumerated() {
            if let idx = entries.firstIndex(where: { $0.id == id }) {
                entries[idx].order = i
                entries[idx].updatedAt = Date()
            }
        }
    }
    func applyReorder(orderedIDs: [UUID]) {
        applyTemplateOrder(orderedIDs)
    }
    func nextOrderValue() -> Int {
        let maxOrder = entries.compactMap { $0.order }.max() ?? -1
        return maxOrder + 1
    }

    // MARK: - Entry CRUD

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
        pushUndoSnapshot()
        let idsToDelete = offsets.map { filtered[$0].id }
        entries.removeAll { idsToDelete.contains($0.id) }
    }

    func toggleFavorite(id: UUID) {
        guard let idx = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[idx].isFavorite.toggle()
        entries[idx].updatedAt = Date()
    }

    func toggleVisibility(id: UUID) {
        guard let idx = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[idx].isVisible.toggle()
        entries[idx].updatedAt = Date()
    }


    func entry(id: UUID) -> LibraryEntry? {
        entries.first(where: { $0.id == id })
    }

    // MARK: - Category Management

    func sortedCategories() -> [CategoryItem] {
        categories.sorted { lhs, rhs in
            if lhs.order != rhs.order { return lhs.order < rhs.order }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    func addCategory(named rawName: String) {
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !categories.contains(where: { $0.name.compare(trimmed, options: .caseInsensitive) == .orderedSame }) else { return }

        let newCategory = CategoryItem(
            id: makeUniqueCategoryID(from: trimmed),
            name: trimmed,
            order: (categories.map(\.order).max() ?? -1) + 1
        )
        categories.append(newCategory)
    }

    func renameCategory(id: EntryCategory, to rawName: String) {
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard id != .general else { return }
        guard !trimmed.isEmpty else { return }
        guard let index = categories.firstIndex(where: { $0.id == id }) else { return }
        guard !categories.contains(where: { $0.id != id && $0.name.compare(trimmed, options: .caseInsensitive) == .orderedSame }) else { return }

        pushUndoSnapshot()
        categories[index].name = trimmed
    }

    func deleteCategory(id: EntryCategory) {
        guard id != .general else { return }
        guard categories.contains(where: { $0.id == id }) else { return }

        pushUndoSnapshot()
        categories.removeAll { $0.id == id }

        var updatedLibraries = libraries
        let now = Date()

        for libraryIndex in updatedLibraries.indices {
            for entryIndex in updatedLibraries[libraryIndex].entries.indices where updatedLibraries[libraryIndex].entries[entryIndex].category == id {
                updatedLibraries[libraryIndex].entries[entryIndex].category = .general
                updatedLibraries[libraryIndex].entries[entryIndex].updatedAt = now
                updatedLibraries[libraryIndex].updatedAt = now
            }
        }

        libraries = updatedLibraries
        normalizeCategoryOrdering()
    }

    func applyCategoryOrder(_ orderedIDs: [EntryCategory]) {
        pushUndoSnapshot()
        for (index, id) in orderedIDs.enumerated() {
            if let categoryIndex = categories.firstIndex(where: { $0.id == id }) {
                categories[categoryIndex].order = index
            }
        }

        normalizeCategoryOrdering()
    }

    private func normalizeCategoryOrdering() {
        let ordered = categories.sorted { lhs, rhs in
            if lhs.order != rhs.order { return lhs.order < rhs.order }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }

        categories = ordered.enumerated().map { index, item in
            var copy = item
            copy.order = index
            return copy
        }
    }

    private func makeUniqueCategoryID(from rawName: String) -> EntryCategory {
        let base = slugifiedCategoryID(from: rawName)
        var candidate = base
        var suffix = 1

        while categories.contains(where: { $0.id.caseInsensitiveCompare(candidate) == .orderedSame }) || candidate == .general {
            candidate = "\(base)-\(suffix)"
            suffix += 1
        }

        return candidate
    }

    private func slugifiedCategoryID(from rawName: String) -> EntryCategory {
        let lowered = rawName.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let collapsedWhitespace = lowered.replacingOccurrences(
            of: #"\s+"#,
            with: "-",
            options: .regularExpression
        )
        let cleaned = collapsedWhitespace.replacingOccurrences(
            of: #"[^a-z0-9-]"#,
            with: "",
            options: .regularExpression
        )
        let collapsedDashes = cleaned.replacingOccurrences(
            of: #"-+"#,
            with: "-",
            options: .regularExpression
        )
        let trimmed = collapsedDashes.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return trimmed.isEmpty ? "category" : trimmed
    }

    // MARK: - Import / Export

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
    private func stampedImportedEntries(_ entries: [LibraryEntry], importedAt: Date) -> [LibraryEntry] {
        entries.map { entry in
            var copy = entry
            copy.lastImportedAt = importedAt
            return copy
        }
    }

    private func measuredPrefixWidth(_ prefix: String, font: UIFont) -> CGFloat {
        ceil((prefix as NSString).size(withAttributes: [.font: font]).width)
    }

    private func importParagraphStyle(
        baseStyle: NSParagraphStyle?,
        baseIndent: CGFloat,
        markerPrefix: String?,
        font: UIFont
    ) -> NSMutableParagraphStyle {
        let style = (baseStyle?.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
        style.tailIndent = 0
        style.paragraphSpacing = 0
        style.paragraphSpacingBefore = 0
        style.lineSpacing = 0

        if let markerPrefix {
            let markerWidth = measuredPrefixWidth(markerPrefix, font: font)
            style.firstLineHeadIndent = baseIndent
            style.headIndent = baseIndent + markerWidth
        } else {
            style.firstLineHeadIndent = baseIndent
            style.headIndent = baseIndent
        }

        return style
    }

    private func importMarkerPrefix(in trimmedParagraph: String) -> String? {
        if trimmedParagraph.hasPrefix("• ") {
            return "• "
        }

        if let range = trimmedParagraph.range(of: "^\\d+\\.\\s", options: .regularExpression) {
            return String(trimmedParagraph[range])
        }

        return nil
    }

    private func normalizedImportedEntryIfNeeded(_ entry: LibraryEntry) -> LibraryEntry {
        guard shouldNormalizeTextOnImport else { return entry }

        var copy = entry
        let cleaned = cleanedAttributedBodyForImport(from: copy.attributedBody)
        copy.setAttributedBody(cleaned)
        copy.updatedAt = Date()
        return copy
    }

    private func cleanedAttributedBodyForImport(from source: NSAttributedString) -> NSAttributedString {
        let currentBaseFont = UIFont.preferredFont(forTextStyle: .title3)
        let regularDescriptor = currentBaseFont.fontDescriptor.withSymbolicTraits(
            currentBaseFont.fontDescriptor.symbolicTraits.subtracting(.traitBold).subtracting(.traitItalic)
        ) ?? currentBaseFont.fontDescriptor
        let baseFont = UIFont(descriptor: regularDescriptor, size: currentBaseFont.pointSize)
        let baseColor = UIColor.label

        let mutable = NSMutableAttributedString(attributedString: source)
        var fullRange = NSRange(location: 0, length: mutable.length)
        guard fullRange.length > 0 else { return source }

        let planRegex = try? NSRegularExpression(pattern: "\\n{3,}(?=Plan:)", options: [.caseInsensitive])
        let normalizedString = NSMutableString(string: mutable.string)
        planRegex?.replaceMatches(in: normalizedString, options: [], range: fullRange, withTemplate: "\n\n")
        mutable.replaceCharacters(in: NSRange(location: 0, length: mutable.length), with: normalizedString as String)
        fullRange = NSRange(location: 0, length: mutable.length)

        mutable.enumerateAttributes(in: fullRange, options: []) { attrs, range, _ in
            mutable.addAttribute(.font, value: baseFont, range: range)
            mutable.addAttribute(.foregroundColor, value: baseColor, range: range)

            if attrs[.backgroundColor] != nil {
                mutable.removeAttribute(.backgroundColor, range: range)
            }
            if attrs[.link] != nil {
                mutable.removeAttribute(.link, range: range)
            }
            if attrs[.strikethroughStyle] != nil {
                mutable.removeAttribute(.strikethroughStyle, range: range)
            }
            if attrs[.underlineStyle] != nil {
                mutable.removeAttribute(.underlineStyle, range: range)
            }
        }

        let normalizedNSString = mutable.string as NSString
        let hasAssessmentOrPlanHeadings =
            normalizedNSString.range(of: "Assessment:", options: .caseInsensitive).location != NSNotFound ||
            normalizedNSString.range(of: "Plan:", options: .caseInsensitive).location != NSNotFound

        let bodyIndent: CGFloat = 16

        var paragraphLocation = 0
        while paragraphLocation < mutable.length {
            let paragraphRange = normalizedNSString.paragraphRange(for: NSRange(location: paragraphLocation, length: 0))
            let paragraphText = normalizedNSString.substring(with: paragraphRange)
            let trimmedParagraph = paragraphText.trimmingCharacters(in: .whitespacesAndNewlines)

            let existingStyle = mutable.attribute(.paragraphStyle, at: paragraphRange.location, effectiveRange: nil) as? NSParagraphStyle
            let baseIndent = hasAssessmentOrPlanHeadings ? bodyIndent : 0
            let nestedIndent = hasAssessmentOrPlanHeadings ? bodyIndent * 2 : bodyIndent
            let style = importParagraphStyle(
                baseStyle: existingStyle,
                baseIndent: importMarkerPrefix(in: trimmedParagraph) == nil ? baseIndent : nestedIndent,
                markerPrefix: importMarkerPrefix(in: trimmedParagraph),
                font: baseFont
            )

            mutable.addAttribute(.paragraphStyle, value: style, range: paragraphRange)

            if trimmedParagraph.caseInsensitiveCompare("Assessment:") == .orderedSame ||
                trimmedParagraph.caseInsensitiveCompare("Plan:") == .orderedSame {
                style.firstLineHeadIndent = 0
                style.headIndent = 0
                mutable.addAttribute(.paragraphStyle, value: style, range: paragraphRange)

                let headingText = trimmedParagraph as NSString
                let headingRange = NSRange(location: paragraphRange.location, length: headingText.length)
                let headingTraits = baseFont.fontDescriptor.symbolicTraits.union(.traitBold)
                let headingFont = UIFont(
                    descriptor: baseFont.fontDescriptor.withSymbolicTraits(headingTraits) ?? baseFont.fontDescriptor,
                    size: baseFont.pointSize
                )
                mutable.addAttribute(.font, value: headingFont, range: headingRange)
                mutable.addAttribute(.foregroundColor, value: baseColor, range: headingRange)
            }

            paragraphLocation = paragraphRange.location + paragraphRange.length
        }

        return mutable
    }
    func exportLibraryJSON() throws -> Data {
        try JSONEncoder.pretty.encode(entries)
    }

    func exportEyeBraryLibraryPackage(to packageURL: URL, libraryName: String = "EYEbrary Library") throws {
        let fm = FileManager.default

        if fm.fileExists(atPath: packageURL.path) {
            try fm.removeItem(at: packageURL)
        }
        try fm.createDirectory(at: packageURL, withIntermediateDirectories: true)

        let entriesDirectoryURL = packageURL.appendingPathComponent("Entries", isDirectory: true)
        try fm.createDirectory(at: entriesDirectoryURL, withIntermediateDirectories: true)

        let manifestEntries: [EyeBraryLibraryManifestEntry] = try entries.map { entry in
            let filename = "\(entry.id.uuidString).rtf"
            let relativePath = "Entries/\(filename)"
            let fileURL = entriesDirectoryURL.appendingPathComponent(filename)

            let rtfData: Data
            if let storedRTF = entry.bodyRTFData {
                rtfData = storedRTF
            } else {
                let attributed = NSAttributedString(string: entry.body)
                rtfData = try attributed.data(
                    from: NSRange(location: 0, length: attributed.length),
                    documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
                )
            }
            try rtfData.write(to: fileURL, options: .atomic)

            return EyeBraryLibraryManifestEntry(
                id: entry.id,
                title: entry.title,
                category: entry.category,
                isFavorite: entry.isFavorite,
                isVisible: entry.isVisible,
                order: entry.order,
                createdAt: entry.createdAt,
                updatedAt: entry.updatedAt,
                lastImportedAt: entry.lastImportedAt,
                contentFile: relativePath
            )
        }

        let manifest = EyeBraryLibraryManifest(
            format: EyeBraryLibraryManifest.currentFormat,
            formatVersion: EyeBraryLibraryManifest.currentFormatVersion,
            libraryName: libraryName,
            exportedAt: Date(),
            entries: manifestEntries
        )

        let manifestData = try JSONEncoder.pretty.encode(manifest)
        let manifestURL = packageURL.appendingPathComponent("manifest.json")
        try manifestData.write(to: manifestURL, options: .atomic)
    }

    func makeTemporaryEyeBraryLibraryPackage(libraryName: String = "EYEbrary Library") throws -> URL {
        let packageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(libraryName)
            .appendingPathExtension("eyebrarylib")

        try exportEyeBraryLibraryPackage(to: packageURL, libraryName: libraryName)
        return packageURL
    }

    func importEyeBraryLibraryPackage(from packageURL: URL, merge: Bool) throws {
        let importedAt = Date()
        let imported = try stampedImportedEntries(
            importEntriesFromEyeBraryLibraryPackage(at: packageURL),
            importedAt: importedAt
        ).map(normalizedImportedEntryIfNeeded)

        pushUndoSnapshot()
        if merge {
            var map = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
            for entry in imported {
                map[entry.id] = entry
            }
            let sorted = Array(map.values).sorted { $0.updatedAt > $1.updatedAt }
            entries = sorted.enumerated().map { index, entry in
                var copy = entry
                copy.order = index
                return copy
            }
        } else {
            let sorted = imported.sorted { $0.updatedAt > $1.updatedAt }
            entries = sorted.enumerated().map { index, entry in
                var copy = entry
                copy.order = index
                return copy
            }
        }
    }

    func importLibraryJSON(_ data: Data, merge: Bool) throws {
        let decoded = try JSONDecoder.standard.decode([LibraryEntry].self, from: data)
        let importedAt = Date()
        let incoming = stampedImportedEntries(
            normalizeImportedEntries(decoded),
            importedAt: importedAt
        ).map(normalizedImportedEntryIfNeeded)

        pushUndoSnapshot()
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

    func deleteEntries(withIDs ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        pushUndoSnapshot()
        entries.removeAll { ids.contains($0.id) }
    }

    func updateEntryCategory(id: UUID, to category: EntryCategory) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        guard entries[index].category != category else { return }
        pushUndoSnapshot()
        entries[index].category = category
        entries[index].updatedAt = Date()
    }

    func updateEntryCategories(ids: Set<UUID>, to category: EntryCategory) {
        guard !ids.isEmpty else { return }
        let now = Date()
        var didChange = false

        for index in entries.indices where ids.contains(entries[index].id) {
            if entries[index].category != category {
                if !didChange {
                    pushUndoSnapshot()
                    didChange = true
                }
                entries[index].category = category
                entries[index].updatedAt = now
            }
        }
    }

    // MARK: - History / Plans

    func addToHistory(patientName: String, reportTitle: String, reportDate: Date, entries: [PlanEntry]) {
        let hasAnyContent = !patientName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                            entries.contains(where: {
                                !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                                !$0.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            })
        guard hasAnyContent else { return }

        let item = SavedPlan(
            id: UUID(),
            patientName: patientName,
            reportTitle: reportTitle,
            reportDate: reportDate,
            entries: entries,
            createdAt: Date(),
            updatedAt: Date()
        )
        plans.insert(item, at: 0)
        plans = Array(plans.prefix(10))
    }
    func addToHistory(reportTitle: String, reportDate: Date, patientName: String, entries: [PlanEntry]) {
        addToHistory(patientName: patientName, reportTitle: reportTitle, reportDate: reportDate, entries: entries)
    }

    func deleteHistory(at offsets: IndexSet) {
        plans.remove(atOffsets: offsets)
    }

    func clearHistory() {
        plans = []
    }
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
        let targetURL = letterheadURL(named: name)

        if FileManager.default.fileExists(atPath: targetURL.path) {
            try FileManager.default.removeItem(at: targetURL)
        }

        letterheads.removeAll { $0 == name }
        safeZoneConfigs[name] = nil

        if selectedLetterheadName == name {
            selectedLetterheadName = letterheads.first
        }
    }

    func safeZoneConfig(named name: String) -> SafeZoneConfig? { safeZoneConfigs[name] }

    func setSafeZoneConfig(_ config: SafeZoneConfig, for name: String) { safeZoneConfigs[name] = config }

    // MARK: - Persistence

    private func loadLibraries() {
        if let data = UserDefaults.standard.data(forKey: librariesKey) {
            do {
                let state = try JSONDecoder.standard.decode(LibrariesState.self, from: data)
                libraries = state.libraries
                activeLibraryID = state.activeLibraryID ?? state.libraries.first?.id
                return
            } catch {
                libraries = []
                activeLibraryID = nil
            }
        }

        guard let data = UserDefaults.standard.data(forKey: templatesKey) else {
            libraries = []
            activeLibraryID = nil
            return
        }

        do {
            let migratedEntries = try JSONDecoder.standard.decode([LibraryEntry].self, from: data)
            let migratedLibrary = makeDefaultLibrary(name: bundledDefaultLibraryName, entries: migratedEntries)
            libraries = [migratedLibrary]
            activeLibraryID = migratedLibrary.id
            persistLibraries()
        } catch {
            libraries = []
            activeLibraryID = nil
        }
    }

    private func persistLibraries() {
        do {
            let state = LibrariesState(libraries: libraries, activeLibraryID: activeLibraryID)
            let data = try JSONEncoder.standard.encode(state)
            UserDefaults.standard.set(data, forKey: librariesKey)
        } catch {
            // ignore
        }
    }

    private func loadCategories() {
        guard let data = UserDefaults.standard.data(forKey: categoriesKey) else {
            categories = []
            return
        }
        do {
            categories = try JSONDecoder.standard.decode([CategoryItem].self, from: data)
        } catch {
            categories = []
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

    private func loadPlans() {
        guard let data = UserDefaults.standard.data(forKey: plansKey) else {
            plans = []
            return
        }
        do {
            plans = try JSONDecoder.standard.decode([SavedPlan].self, from: data)
        } catch {
            plans = []
        }
    }

    private func persistPlans() {
        do {
            let data = try JSONEncoder.standard.encode(plans)
            UserDefaults.standard.set(data, forKey: plansKey)
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
            let state = try JSONDecoder.standard.decode(LetterheadState.self, from: data)
            letterheads = state.letterheads
            selectedLetterheadName = state.selectedLetterheadName
        } catch {
            letterheads = []
            selectedLetterheadName = nil
        }
    }

    private func persistLetterheads() {
        do {
            let state = LetterheadState(letterheads: letterheads, selectedLetterheadName: selectedLetterheadName)
            let data = try JSONEncoder.standard.encode(state)
            UserDefaults.standard.set(data, forKey: letterheadsKey)
        } catch {
            // ignore
        }
    }

    private func loadSafeZoneConfigs() {
        guard let data = UserDefaults.standard.data(forKey: safeZoneConfigsKey) else {
            safeZoneConfigs = [:]
            return
        }
        do {
            safeZoneConfigs = try JSONDecoder.standard.decode([String: SafeZoneConfig].self, from: data)
        } catch {
            safeZoneConfigs = [:]
        }
    }

    private func persistSafeZoneConfigs() {
        do {
            let data = try JSONEncoder.standard.encode(safeZoneConfigs)
            UserDefaults.standard.set(data, forKey: safeZoneConfigsKey)
        } catch {
            // ignore
        }
    }

    // MARK: - Defaults / Reset

    private func loadBundledDefaultLibraryIfAvailable() -> [LibraryEntry]? {
        guard let packageURL = Bundle.main.url(
            forResource: bundledDefaultLibraryName,
            withExtension: bundledDefaultLibraryExtension
        ) else {
            return nil
        }

        do {
            return try importBundledDefaultLibraryPackage(at: packageURL)
        } catch {
            return nil
        }
    }

    private func importBundledDefaultLibraryPackage(at packageURL: URL) throws -> [LibraryEntry] {
        let manifestURL = packageURL.appendingPathComponent("manifest.json")
        let manifestData = try Data(contentsOf: manifestURL)
        let manifest = try JSONDecoder.standard.decode(EyeBraryLibraryManifest.self, from: manifestData)

        guard manifest.format == EyeBraryLibraryManifest.currentFormat,
              manifest.formatVersion == EyeBraryLibraryManifest.currentFormatVersion else {
            throw CocoaError(.fileReadCorruptFile)
        }

        let importedEntries: [LibraryEntry] = try manifest.entries.map { item in
            let contentURL = packageURL.appendingPathComponent(item.contentFile)
            let rtfData = try Data(contentsOf: contentURL)

            let attributed = try NSAttributedString(
                data: rtfData,
                options: [.documentType: NSAttributedString.DocumentType.rtf],
                documentAttributes: nil
            )

            return LibraryEntry(
                id: item.id,
                title: item.title,
                body: attributed.string,
                bodyRTFData: rtfData,
                category: normalizedCategoryID(item.category),
                isFavorite: item.isFavorite,
                isVisible: item.isVisible,
                order: item.order,
                createdAt: item.createdAt,
                updatedAt: item.updatedAt,
                lastImportedAt: item.lastImportedAt
            )
        }

        return importedEntries
    }

    private func importEntriesFromEyeBraryLibraryPackage(at packageURL: URL) throws -> [LibraryEntry] {
        let manifestURL = packageURL.appendingPathComponent("manifest.json")
        let manifestData = try Data(contentsOf: manifestURL)
        let manifest = try JSONDecoder.standard.decode(EyeBraryLibraryManifest.self, from: manifestData)

        guard manifest.format == EyeBraryLibraryManifest.currentFormat,
              manifest.formatVersion == EyeBraryLibraryManifest.currentFormatVersion else {
            throw CocoaError(.fileReadCorruptFile)
        }

        let importedEntries: [LibraryEntry] = try manifest.entries.map { item in
            let contentURL = packageURL.appendingPathComponent(item.contentFile)
            let rtfData = try Data(contentsOf: contentURL)

            let attributed = try NSAttributedString(
                data: rtfData,
                options: [.documentType: NSAttributedString.DocumentType.rtf],
                documentAttributes: nil
            )

            return LibraryEntry(
                id: item.id,
                title: item.title,
                body: attributed.string,
                bodyRTFData: rtfData,
                category: item.category,
                isFavorite: item.isFavorite,
                isVisible: item.isVisible,
                order: item.order,
                createdAt: item.createdAt,
                updatedAt: item.updatedAt,
                lastImportedAt: item.lastImportedAt
            )
        }

        return normalizeImportedEntries(importedEntries)
    }

    private func seedDefaults() {
        let library = makeDefaultLibrary(
            name: bundledDefaultLibraryName,
            entries: loadBundledDefaultLibraryIfAvailable() ?? factoryDefaultTemplates()
        )
        libraries = [library]
        activeLibraryID = library.id
    }

    func resetToFactoryDefaults() {
        let library = makeDefaultLibrary(
            name: bundledDefaultLibraryName,
            entries: loadBundledDefaultLibraryIfAvailable() ?? factoryDefaultTemplates()
        )
        libraries = [library]
        activeLibraryID = library.id
        categories = defaultCategories()
        plans = []
        letterheads = []
        selectedLetterheadName = nil
        UserDefaults.standard.removeObject(forKey: launchAcknowledgementKey)
    }

    private func seedDefaultCategories() {
        categories = defaultCategories()
    }

    private func defaultCategories() -> [CategoryItem] {
        [
            CategoryItem(id: .general, name: "General", order: 0),
            CategoryItem(id: "lids", name: "Lids", order: 1),
            CategoryItem(id: "cornea", name: "Cornea", order: 2),
            CategoryItem(id: "anterior-segment", name: "Anterior Segment", order: 3),
            CategoryItem(id: "posterior-segment", name: "Posterior Segment", order: 4),
            CategoryItem(id: "retina", name: "Retina", order: 5),
            CategoryItem(id: "glaucoma", name: "Glaucoma", order: 6),
            CategoryItem(id: "neuro", name: "Neuro", order: 7),
            CategoryItem(id: "binocular-vision", name: "Binocular Vision", order: 8),
            CategoryItem(id: "pediatrics", name: "Pediatrics", order: 9),
            CategoryItem(id: "instructions", name: "Instructions", order: 10),
            CategoryItem(id: "information", name: "Information", order: 11)
        ]
    }

    private func factoryDefaultTemplates() -> [LibraryEntry] {
        []
    }
}
