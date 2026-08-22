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

            if viewModel.skippedCount > 0 {
                Text("\(viewModel.skippedCount) non-Live Photo(s) skipped")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            Spacer()
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(project.title)
                    .font(.headline)
            }
        }
        .task {
            await viewModel.extract(project: project, modelContext: modelContext)
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

        // VlogClip は @Model なので Sendable ではない。子タスクには値だけ渡す
        let targets = clips.map { (id: $0.id, sourceID: $0.sourceCloudID) }
        let extractor = self.extractor

        let run: @Sendable (UUID, String) async -> (UUID, URL?) = { id, sourceID in
            do {
                let url = sourceID.contains("/")
                    ? try await extractor.extractVideo(fromLocalID: sourceID)
                    : try await extractor.extractVideo(fromCloudID: sourceID)
                return (id, url)
            } catch {
                print("Failed to extract clip \(id): \(error)")
                return (id, nil)
            }
        }

        var failedIDs: Set<UUID> = []

        await withTaskGroup(of: (UUID, URL?).self) { group in
            var next = 0
            while next < min(LivePhotoExtractor.maxConcurrent, targets.count) {
                let target = targets[next]
                next += 1
                group.addTask { await run(target.id, target.sourceID) }
            }

            for await (id, url) in group {
                if let url {
                    extractedURLs[id] = url
                } else {
                    failedIDs.insert(id)
                }

                completedCount += 1
                progress = Double(completedCount) / Double(totalCount)

                if next < targets.count {
                    let target = targets[next]
                    next += 1
                    group.addTask { await run(target.id, target.sourceID) }
                }
            }
        }

        let failedClips = clips.filter { failedIDs.contains($0.id) }

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
