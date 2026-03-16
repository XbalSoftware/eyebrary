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
