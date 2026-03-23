import SwiftUI
import Foundation
import UIKit

//
//  SharingHelpers.swift
//  EYEbrary
//
//  Created by Simon Reid on 2026-03-15.
//

// MARK: - Sharing helpers

struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
// MARK: - Single Entry JSON Export

struct ExportableLibraryEntry: Codable {
    let id: UUID
    let title: String
    let body: String
    let category: String
    let isFavorite: Bool
    let isVisible: Bool
    let createdAt: Date
    let updatedAt: Date
}

func exportEntryAsJSON(_ entry: LibraryEntry) throws -> Data {
    let exportEntry = ExportableLibraryEntry(
        id: entry.id,
        title: entry.title,
        body: entry.attributedBody.string, // flatten to plain text
        category: entry.category,
        isFavorite: entry.isFavorite,
        isVisible: entry.isVisible,
        createdAt: entry.createdAt,
        updatedAt: entry.updatedAt
    )

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601

    return try encoder.encode([exportEntry]) // one-element array
}
