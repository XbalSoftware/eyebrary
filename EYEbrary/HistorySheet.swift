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
                        description: Text("Cleared plans are saved here (up to 10)\n- patient names omitted for privacy -")
                    )
                    Spacer()
                } else {
                    List {
                        Section {
                            ForEach(history) { item in
                                Button {
                                    onRestore(item)
                                } label: {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(item.patientName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "- patient name not retained for privacy -" : item.patientName)
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
            }
        }
        .navigationTitle("Recent Reports")
        .navigationBarTitleDisplayMode(.inline)
    }
}
