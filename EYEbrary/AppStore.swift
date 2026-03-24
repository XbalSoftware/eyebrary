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

    enum CodingKeys: String, CodingKey {
        case id, title, body, bodyRTFData, assessment, plan, category, defaultStyle, isFavorite, isPinned, isVisible, order, createdAt, updatedAt, level
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
        updatedAt: Date = Date()
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
    // Entries
    @Published var entries: [LibraryEntry] = [] {
        didSet { persistTemplates() }
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
    var history: [SavedPlan] {
        get { plans }
        set { plans = newValue }
    }
    private let templatesKey = "EYEbrary.conditionTemplates.v1"
    private let categoriesKey = "EYEbrary.categories.v1"
    private let plansKey = "EYEbrary.savedPlans.v1"
    private let letterheadsKey = "EYEbrary.letterheads.v1"
    private let launchAcknowledgementKey = "EYEbrary.hasAcknowledgedAppInformation.v1"
    private let bundledDefaultLibraryName = "Default Library"
    private let bundledDefaultLibraryExtension = "eyebrarylib"
    private let normalizeTextOnImportKey = "EYEbrary.normalizeTextOnImport.v1"

    private var shouldNormalizeTextOnImport: Bool {
        if UserDefaults.standard.object(forKey: normalizeTextOnImportKey) == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: normalizeTextOnImportKey)
    }
    
    init() {
        loadCategories()
        loadTemplates()
        loadPlans()
        loadLetterheads()
        if categories.isEmpty { seedDefaultCategories() }
        if entries.isEmpty { seedDefaults() }
        ensureTemplateOrdering()
    }

    // MARK: - Ordering

    private func ensureTemplateOrdering() {
        if entries.allSatisfy({ $0.order != nil }) { return }

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

        entries = entries
    }

    func applyTemplateOrder(_ orderedIDs: [UUID]) {
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

        categories[index].name = trimmed
    }

    func deleteCategory(id: EntryCategory) {
        guard id != .general else { return }
        guard categories.contains(where: { $0.id == id }) else { return }

        categories.removeAll { $0.id == id }

        for index in entries.indices where entries[index].category == id {
            entries[index].category = .general
            entries[index].updatedAt = Date()
        }

        normalizeCategoryOrdering()
    }

    func applyCategoryOrder(_ orderedIDs: [EntryCategory]) {
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
        let bulletIndent = ceil(("• " as NSString).size(withAttributes: [.font: baseFont]).width)
        let numberIndent = ceil(("1. " as NSString).size(withAttributes: [.font: baseFont]).width)

        var paragraphLocation = 0
        while paragraphLocation < mutable.length {
            let paragraphRange = normalizedNSString.paragraphRange(for: NSRange(location: paragraphLocation, length: 0))
            let paragraphText = normalizedNSString.substring(with: paragraphRange)
            let trimmedParagraph = paragraphText.trimmingCharacters(in: .whitespacesAndNewlines)

            let existingStyle = mutable.attribute(.paragraphStyle, at: paragraphRange.location, effectiveRange: nil) as? NSParagraphStyle
            let style = (existingStyle?.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()

            style.firstLineHeadIndent = hasAssessmentOrPlanHeadings ? bodyIndent : 0
            style.headIndent = hasAssessmentOrPlanHeadings ? bodyIndent : 0
            style.tailIndent = 0
            style.paragraphSpacing = 0
            style.paragraphSpacingBefore = 0
            style.lineSpacing = 0

            if trimmedParagraph.range(of: "^\\d+\\.\\s", options: .regularExpression) != nil {
                if hasAssessmentOrPlanHeadings {
                    style.firstLineHeadIndent = bodyIndent * 2
                    style.headIndent = (bodyIndent * 2) + numberIndent
                } else {
                    style.firstLineHeadIndent = bodyIndent
                    style.headIndent = bodyIndent + numberIndent
                }
            } else if trimmedParagraph.hasPrefix("• ") {
                if hasAssessmentOrPlanHeadings {
                    style.firstLineHeadIndent = bodyIndent * 2
                    style.headIndent = (bodyIndent * 2) + bulletIndent
                } else {
                    style.firstLineHeadIndent = bodyIndent
                    style.headIndent = bodyIndent + bulletIndent
                }
            }

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
        let imported = try importEntriesFromEyeBraryLibraryPackage(at: packageURL).map(normalizedImportedEntryIfNeeded)

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
        let incoming = normalizeImportedEntries(decoded).map(normalizedImportedEntryIfNeeded)

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
    // MARK: - Persistence

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

    // MARK: - Defaults / Reset

    private func loadBundledDefaultLibraryIfAvailable() -> [LibraryEntry]? {
        guard let packageURL = Bundle.main.url(
            forResource: bundledDefaultLibraryName,
            withExtension: bundledDefaultLibraryExtension
        ) else {
            return nil
        }

        do {
            return try importEntriesFromEyeBraryLibraryPackage(at: packageURL)
        } catch {
            return nil
        }
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
                updatedAt: item.updatedAt
            )
        }

        return normalizeImportedEntries(importedEntries)
    }

    private func seedDefaults() {
        entries = loadBundledDefaultLibraryIfAvailable() ?? factoryDefaultTemplates()
    }

    func resetToFactoryDefaults() {
        entries = loadBundledDefaultLibraryIfAvailable() ?? factoryDefaultTemplates()
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
            CategoryItem(id: "dryEye", name: "Dry Eye", order: 1),
            CategoryItem(id: "glaucoma", name: "Glaucoma", order: 2),
            CategoryItem(id: "retina", name: "Retina", order: 3),
            CategoryItem(id: "neuro", name: "Neuro", order: 4)
        ]
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
}
