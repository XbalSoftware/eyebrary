import SwiftUI
import Foundation

//
//  HistorySheet.swift
//  EYEbrary
//
//  Created by Simon Reid on 2026-03-15.
//

// MARK: - HistorySheet

struct HistorySheet: View {
    let history: [SavedPlan]
    let onRestore: (SavedPlan) -> Void
    let onDelete: (IndexSet) -> Void
    let onClearAll: () -> Void

    @Environment(\.dismiss) private var dismiss

    private func entrySummary(for item: SavedPlan) -> String {
        let titles = item.entries
            .map { $0.title.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let preview = titles.prefix(3).joined(separator: ", ")
        let suffix = titles.count > 3 ? "…" : ""
        let itemCount = item.entries.count
        return "\(itemCount) item\(itemCount == 1 ? "" : "s") · \(preview)\(suffix)"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    Button("Clear All", role: .destructive) {
                        onClearAll()
                    }
                    .buttonStyle(.bordered)
                    .disabled(history.isEmpty)

                    Spacer()

                    Text("Recent Reports")
                        .font(.title3.weight(.semibold))

                    Spacer()

                    Button("Done") {
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 2)
                .background(Color.black.opacity(0.35))

                if history.isEmpty {
                    Spacer()
                    ContentUnavailableView(
                        "No history",
                        systemImage: "clock",
                        description: Text("Cleared plans are saved here (up to 10). Patient names are omitted for privacy.")
                    )
                    Spacer()
                } else {
                    VStack(spacing: 0) {
                        HStack {
                            Text("Patient names are not stored for privacy")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal)
                        .padding(.top, 10)
                        .padding(.bottom, 6)

                        List {
                            Section {
                                ForEach(history) { item in
                                    Button {
                                        onRestore(item)
                                    } label: {
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text(entrySummary(for: item))
                                                .font(.headline)
                                                .lineLimit(1)
                                                .truncationMode(.tail)

                                            Text(item.createdAt.formatted(date: .abbreviated, time: .shortened))
                                                .font(.subheadline)
                                                .foregroundStyle(.secondary)
                                        }
                                        .padding(.vertical, 6)
                                    }
                                }
                                .onDelete(perform: onDelete)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Recent Reports")
        .navigationBarTitleDisplayMode(.inline)
    }
}
