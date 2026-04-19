//
//  ExtractingView.swift
//  Madeleine
//
//  Created by satoshikobayashi on 2026/04/19.
//

import SwiftUI

struct ExtractingView: View {
    let project: VlogProject
    let onComplete: ([UUID: URL]) -> Void

    @State private var viewModel = ExtractingViewModel()

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            ProgressView(value: viewModel.progress) {
                Text("Extracting Live Photos…")
                    .font(.headline)
            } currentValueLabel: {
                Text("\(viewModel.completedCount) / \(viewModel.totalCount)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 40)

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Spacer()
        }
        .navigationTitle("Extracting")
        .navigationBarBackButtonHidden()
        .task {
            await viewModel.extract(project: project)
            onComplete(viewModel.extractedURLs)
        }
    }
}

// MARK: - ViewModel

@Observable
@MainActor
final class ExtractingViewModel {
    var progress: Double = 0
    var completedCount: Int = 0
    var totalCount: Int = 0
    var errorMessage: String?

    private(set) var extractedURLs: [UUID: URL] = [:]

    private let extractor = LivePhotoExtractor()

    func extract(project: VlogProject) async {
        let clips = (project.clips ?? []).sorted { $0.order < $1.order }
        totalCount = clips.count
        guard totalCount > 0 else { return }

        for clip in clips {
            do {
                // sourceCloudID には現在 localIdentifier が入っている
                // iCloud Photos が有効な環境では cloudIdentifier に変換される
                let sourceID = clip.sourceCloudID
                let url: URL
                if sourceID.contains("/") {
                    // localIdentifier の形式（例: "ABC123/L0/001"）
                    url = try await extractor.extractVideo(fromLocalID: sourceID)
                } else {
                    // cloudIdentifier の形式
                    url = try await extractor.extractVideo(fromCloudID: sourceID)
                }
                extractedURLs[clip.id] = url
            } catch {
                print("Failed to extract clip \(clip.id): \(error)")
            }

            completedCount += 1
            progress = Double(completedCount) / Double(totalCount)
        }

        if extractedURLs.isEmpty {
            errorMessage = "No Live Photos could be extracted."
        }
    }
}
