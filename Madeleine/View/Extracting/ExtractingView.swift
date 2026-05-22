//
//  ExtractingView.swift
//  Madeleine
//
//  Created by satoshikobayashi on 2026/04/19.
//

import SwiftUI
import SwiftData
import Photos

struct ExtractingView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let project: VlogProject
    let onComplete: ([UUID: URL]) -> Void

    @State private var viewModel = ExtractingViewModel()

    private var isError: Bool {
        viewModel.isComplete && viewModel.extractedURLs.isEmpty
    }

    var body: some View {
        Group {
            if isError {
                ContentUnavailableView(
                    "No Live Photos Found",
                    systemImage: "exclamationmark.triangle",
                    description: Text("None of the selected photos could be extracted.")
                )
            } else {
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

                    if viewModel.skippedCount > 0 {
                        Text("\(viewModel.skippedCount) non-Live Photo(s) skipped")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    Spacer()
                }
            }
        }
        .navigationTitle("Extracting")
        .navigationBarBackButtonHidden()
        .toolbar {
            if isError {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text("Back")
                        }
                    }
                }
            }
        }
        .task {
            await viewModel.extract(project: project, modelContext: modelContext)
            if !viewModel.extractedURLs.isEmpty {
                onComplete(viewModel.extractedURLs)
            }
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
    var skippedCount: Int = 0
    var isComplete = false

    private(set) var extractedURLs: [UUID: URL] = [:]

    private let extractor = LivePhotoExtractor()

    func extract(project: VlogProject, modelContext: ModelContext) async {
        let clips = (project.clips ?? []).sorted { $0.order < $1.order }
        totalCount = clips.count
        guard totalCount > 0 else {
            isComplete = true
            return
        }

        // 権限がない場合はクリップを削除せずにエラー状態にする
        let authStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard authStatus == .authorized || authStatus == .limited else {
            isComplete = true
            return
        }

        var failedClips: [VlogClip] = []

        for clip in clips {
            do {
                let sourceID = clip.sourceCloudID
                let url: URL
                if sourceID.contains("/") {
                    url = try await extractor.extractVideo(fromLocalID: sourceID)
                } else {
                    url = try await extractor.extractVideo(fromCloudID: sourceID)
                }
                extractedURLs[clip.id] = url
            } catch {
                print("Failed to extract clip \(clip.id): \(error)")
                failedClips.append(clip)
            }

            completedCount += 1
            progress = Double(completedCount) / Double(totalCount)
        }

        // 抽出に失敗したクリップを削除して順序を詰める
        for clip in failedClips {
            modelContext.delete(clip)
        }
        let remaining = (project.clips ?? []).sorted { $0.order < $1.order }
        for (index, clip) in remaining.enumerated() {
            clip.order = index
        }

        if !failedClips.isEmpty {
            skippedCount = failedClips.count
        }

        isComplete = true
    }
}
