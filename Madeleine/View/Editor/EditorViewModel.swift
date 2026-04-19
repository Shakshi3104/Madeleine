//
//  EditorViewModel.swift
//  Madeleine
//
//  Created by satoshikobayashi on 2026/04/19.
//

import SwiftUI
import SwiftData
import AVFoundation

enum VideoOrientation: String, CaseIterable {
    case portrait = "Portrait"
    case landscape = "Landscape"

    var renderSize: CGSize {
        switch self {
        case .portrait: CGSize(width: 1080, height: 1920)
        case .landscape: CGSize(width: 1920, height: 1080)
        }
    }

    var systemImage: String {
        switch self {
        case .portrait: "rectangle.portrait.rotate"
        case .landscape: "rectangle.landscape.rotate"
        }
    }
}

@Observable
@MainActor
final class EditorViewModel {
    var project: VlogProject
    var extractedURLs: [UUID: URL]
    var orientation: VideoOrientation = .portrait
    var isGeneratingPreview = false
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
        isGeneratingPreview = true
        defer { isGeneratingPreview = false }

        do {
            let result = try await composer.compose(
                clips: sortedClips,
                videoURLs: extractedURLs,
                renderSize: orientation.renderSize
            )
            let url = try await exporter.export(
                composition: result.0,
                videoComposition: result.1
            )
            previewURL = url
            showPreview = true
        } catch {
            errorMessage = "Preview failed: \(error)"
        }
    }

    // MARK: - Export & Share

    func exportAndShare() async {
        isExporting = true

        do {
            let result = try await composer.compose(
                clips: sortedClips,
                videoURLs: extractedURLs,
                renderSize: orientation.renderSize
            )
            let tempURL = try await exporter.export(
                composition: result.0,
                videoComposition: result.1
            )
            // 共有用に適切なファイル名をつける
            let sanitizedTitle = project.title
                .lowercased()
                .replacingOccurrences(of: " ", with: "-")
            let namedURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(sanitizedTitle).mov")
            try? FileManager.default.removeItem(at: namedURL)
            try FileManager.default.copyItem(at: tempURL, to: namedURL)
            exportedFileURL = namedURL
            project.updatedAt = .now

            isExporting = false
            showShareSheet = true
        } catch {
            isExporting = false
            errorMessage = "Export failed: \(error.localizedDescription)"
        }
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
