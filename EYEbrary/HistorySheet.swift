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

    var body: some View {
        NavigationStack {
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
                                    Text(item.createdAt.formatted(date: .abbreviated, time: .shortened))
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
