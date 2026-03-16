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

// MARK: - Root

struct ContentView: View {
    @StateObject private var store = AppStore()
    
    @State private var showLaunchAcknowledgement: Bool = false

    private let launchAcknowledgementKey = "EYEbrary.hasAcknowledgedAppInformation.v1"

    private var launchAcknowledgementMessage: String {
        "EYEbrary is a report-generation tool intended for use by qualified eye care professionals.\n\nDefault library entries are provided as editable templates and may not reflect current clinical guidance.\n\nAll information included in a generated report must be reviewed and approved by the practitioner before being provided to a patient."
    }

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
        .onAppear {
            if !UserDefaults.standard.bool(forKey: launchAcknowledgementKey) {
                showLaunchAcknowledgement = true
            }
        }
        .alert("App Information", isPresented: $showLaunchAcknowledgement) {
            Button("Continue") {
                UserDefaults.standard.set(true, forKey: launchAcknowledgementKey)
            }
        } message: {
            Text(launchAcknowledgementMessage)
        }
    }
}




// MARK: - Filtering Helpers

enum CategoryFilter: Equatable {
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

func matchesCategory(_ t: LibraryEntry, filter: CategoryFilter) -> Bool {
    switch filter {
    case .all:
        return true
    case .category(let id):
        return t.category == id
    }
}
