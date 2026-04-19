//
//  EditorViewModel.swift
//  Madeleine
//
//  Created by satoshikobayashi on 2026/04/19.
//

import SwiftUI
import SwiftData
import AVFoundation
import PhotosUI
import Photos

enum VideoOrientation: String, CaseIterable {
    case portrait
    case landscape

    var renderSize: CGSize {
        switch self {
        case .portrait: CGSize(width: 1080, height: 1920)
        case .landscape: CGSize(width: 1920, height: 1080)
        }
    }

    var displayName: String {
        switch self {
        case .portrait: "Portrait"
        case .landscape: "Landscape"
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
    var isAddingClips = false
    var exportProgress: Double = 0
    var showExportProgress = false
    var showPreview = false
    var showShareSheet = false
    var previewURL: URL?
    var exportedFileURL: URL?
    var errorMessage: String?

    private let composer = VideoComposer()
    private let exporter = VideoExporter()
    private let extractor = LivePhotoExtractor()

    var loadingMessage: String {
        if isAddingClips { return "Adding Live Photos…" }
        if isExporting { return "Exporting…" }
        return "Generating Preview…"
    }

    var sortedClips: [VlogClip] {
        (project.clips ?? []).sorted { $0.order < $1.order }
    }

    init(project: VlogProject, extractedURLs: [UUID: URL]) {
        self.project = project
        self.extractedURLs = extractedURLs
        self.orientation = VideoOrientation(rawValue: project.orientationRaw) ?? .portrait
    }

    func updateOrientation(_ newValue: VideoOrientation) {
        orientation = newValue
        project.orientationRaw = newValue.rawValue
        project.updatedAt = .now
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

    // MARK: - Add Clips

    func addClips(from items: [PhotosPickerItem], modelContext: ModelContext) async {
        isAddingClips = true
        defer { isAddingClips = false }

        let currentMaxOrder = sortedClips.last?.order ?? -1
        let existingIDs = Set(sortedClips.map(\.sourceCloudID))
        var addedCount = 0

        for item in items {
            guard let localID = item.itemIdentifier else { continue }
            guard !existingIDs.contains(localID) else { continue }

            let assets = PHAsset.fetchAssets(withLocalIdentifiers: [localID], options: nil)
            let filename = assets.firstObject.flatMap {
                PHAssetResource.assetResources(for: $0).first?.originalFilename
            } ?? ""
            let captureDate = assets.firstObject?.creationDate

            let clip = VlogClip(
                order: currentMaxOrder + 1 + addedCount,
                sourceCloudID: localID,
                originalFilename: filename,
                captureDate: captureDate
            )
            clip.project = project
            modelContext.insert(clip)

            // 動画を抽出
            do {
                let url = try await extractor.extractVideo(fromLocalID: localID)
                extractedURLs[clip.id] = url
                addedCount += 1
            } catch {
                print("Failed to extract added clip \(clip.id): \(error)")
                modelContext.delete(clip)
            }
        }

        reorderClips()
        project.updatedAt = .now
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
