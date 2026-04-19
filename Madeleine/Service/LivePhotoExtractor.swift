//
//  LivePhotoExtractor.swift
//  Madeleine
//
//  Created by satoshikobayashi on 2026/04/19.
//

import Photos

actor LivePhotoExtractor {
    enum ExtractError: Error {
        case assetNotFound
        case notLivePhoto
        case noPairedVideo
        case writeFailed(Error)
    }

    private let resolver = CloudIdentifierResolver()

    /// localIdentifier から直接抽出
    func extractVideo(fromLocalID localID: String) async throws -> URL {
        guard let asset = PHAsset.fetchAssets(
            withLocalIdentifiers: [localID], options: nil
        ).firstObject else {
            throw ExtractError.assetNotFound
        }
        return try await extractVideo(from: asset)
    }

    /// cloudIdentifier から抽出
    func extractVideo(fromCloudID cloudID: String) async throws -> URL {
        let asset = try await resolver.asset(fromCloud: cloudID)
        return try await extractVideo(from: asset)
    }

    /// PHAsset から paired video を抽出
    private func extractVideo(from asset: PHAsset) async throws -> URL {
        guard asset.mediaSubtypes.contains(.photoLive) else {
            throw ExtractError.notLivePhoto
        }

        let resources = PHAssetResource.assetResources(for: asset)
        guard let videoResource = resources.first(where: { $0.type == .pairedVideo })
        else { throw ExtractError.noPairedVideo }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")

        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true

        return try await withCheckedThrowingContinuation { continuation in
            PHAssetResourceManager.default().writeData(
                for: videoResource, toFile: outputURL, options: options
            ) { error in
                if let error {
                    continuation.resume(throwing: ExtractError.writeFailed(error))
                } else {
                    continuation.resume(returning: outputURL)
                }
            }
        }
    }
}
