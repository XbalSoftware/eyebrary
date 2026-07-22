//
//  AppBackup.swift
//  EYEbrary
//
//  One-file backup/restore of the whole app: every library (entries with
//  their rich text), the global categories, and every letterhead (PDF bytes
//  + calibrated safe-zone settings + the active selection). Exported and
//  imported from Settings → Backup as a Files-app JSON — the quick-restore
//  path around a reset, a device migration, or a fresh install.
//
//  Report history and the in-progress draft are deliberately excluded: a
//  backup file lives outside the app, so nothing report-shaped leaves with it.
//

import Foundation
import SwiftUI
import UniformTypeIdentifiers

nonisolated struct EYEbraryBackup: Codable {
    /// Bumped if the shape ever changes incompatibly; import currently
    /// accepts anything that decodes.
    var version: Int = 1
    var exportedAt: Date = Date()

    var libraries: [LibraryCollection] = []
    var activeLibraryID: UUID? = nil
    var categories: [CategoryItem] = []
    var letterheads: [BackupLetterhead] = []
    var selectedLetterheadName: String? = nil
}

/// A letterhead travels as its PDF bytes plus its safe-zone calibration, so a
/// restore reproduces both the artwork and the content rectangle.
nonisolated struct BackupLetterhead: Codable {
    var name: String
    var pdfData: Data
    var safeZoneConfig: SafeZoneConfig?
}

enum AppBackupError: LocalizedError {
    case emptyBackup

    var errorDescription: String? {
        switch self {
        case .emptyBackup:
            return "This file doesn't contain any libraries, so it isn't a valid EYEbrary backup."
        }
    }
}

/// Minimal FileDocument wrapper for `.fileExporter`. Reading back through
/// this type is never used — import goes through `.fileImporter` + JSONDecoder.
struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    let backup: EYEbraryBackup

    init(backup: EYEbraryBackup) { self.backup = backup }

    init(configuration: ReadConfiguration) throws {
        let data = configuration.file.regularFileContents ?? Data()
        backup = try JSONDecoder.standard.decode(EYEbraryBackup.self, from: data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: try JSONEncoder.standard.encode(backup))
    }
}
