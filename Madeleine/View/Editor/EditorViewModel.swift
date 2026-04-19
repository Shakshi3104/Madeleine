//
//  EditorViewModel.swift
//  Madeleine
//
//  Created by satoshikobayashi on 2026/04/19.
//

import SwiftUI
import SwiftData
import AVFoundation

@Observable
@MainActor
final class EditorViewModel {
    var project: VlogProject
    var extractedURLs: [UUID: URL]
    var isExporting = false
    var exportProgress: Double = 0
    var showExportProgress = false
    var showPreview = false
    var showShareSheet = false
    var previewURL: URL?
    var exportedFileURL: URL?
    var errorMessage: String?

    private let composer = VideoComposer()
    private let exporter = VideoExporter()

    var sortedClips: [VlogClip] {
        (project.clips ?? []).sorted { $0.order < $1.order }
    }

    init(project: VlogProject, extractedURLs: [UUID: URL]) {
        self.project = project
        self.extractedURLs = extractedURLs
    }

    // MARK: - Preview

    func generatePreview() async {
        let clips = sortedClips
        print("🎬 generatePreview: \(clips.count) clips, \(extractedURLs.count) URLs")
        for clip in clips {
            let hasURL = extractedURLs[clip.id] != nil
            print("  clip \(clip.order): id=\(clip.id), hasURL=\(hasURL)")
        }

        do {
            print("🎬 Starting compose...")
            let result = try await composer.compose(
                clips: clips,
                videoURLs: extractedURLs
            )
            print("🎬 Compose done. Starting export...")
            let url = try await exporter.export(
                composition: result.0,
                videoComposition: result.1
            )
            print("🎬 Export done: \(url)")
            previewURL = url
            showPreview = true
        } catch {
            print("🎬 ERROR: \(error)")
            errorMessage = "Preview failed: \(error)"
        }
    }

    // MARK: - Export & Share

    func exportAndShare() async {
        isExporting = true
        showExportProgress = true
        exportProgress = 0.2

        do {
            let result = try await composer.compose(
                clips: sortedClips,
                videoURLs: extractedURLs
            )
            exportProgress = 0.5

            let outputURL = try await exporter.export(
                composition: result.0,
                videoComposition: result.1
            )
            exportProgress = 1.0
            exportedFileURL = outputURL
            project.updatedAt = .now

            // ExportProgressView を閉じてから共有シートを表示
            showExportProgress = false
            try await Task.sleep(for: .milliseconds(800))
            showShareSheet = true
        } catch {
            errorMessage = "Export failed: \(error.localizedDescription)"
        }

        isExporting = false
    }

    // MARK: - Clip Management

    func deleteClip(_ clip: VlogClip, modelContext: ModelContext) {
        extractedURLs.removeValue(forKey: clip.id)
        modelContext.delete(clip)
        reorderClips()
        project.updatedAt = .now
    }

    func moveClips(from source: IndexSet, to destination: Int) {
        var clips = sortedClips
        clips.move(fromOffsets: source, toOffset: destination)
        for (index, clip) in clips.enumerated() {
            clip.order = index
        }
        project.updatedAt = .now
    }

    private func reorderClips() {
        for (index, clip) in sortedClips.enumerated() {
            clip.order = index
        }
    }
}
