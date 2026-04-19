//
//  VideoExporter.swift
//  Madeleine
//
//  Created by satoshikobayashi on 2026/04/19.
//

import AVFoundation

struct VideoExporter {
    enum ExportError: Error {
        case exportFailed(String)
        case cancelled
    }

    /// AVComposition + AVVideoComposition → 一時ファイルに書き出し、URLを返す
    func export(
        composition: AVComposition,
        videoComposition: AVVideoComposition
    ) async throws -> URL {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")

        let session = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        )
        guard let session else {
            throw ExportError.exportFailed("Failed to create export session")
        }

        session.videoComposition = videoComposition
        try await session.export(to: outputURL, as: .mov)
        return outputURL
    }
}
