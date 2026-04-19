//
//  PhotoLibrarySaver.swift
//  Madeleine
//
//  Created by satoshikobayashi on 2026/04/19.
//

import Photos

struct PhotoLibrarySaver {
    enum SaveError: Error {
        case saveFailed(Error)
        case noIdentifier
        case noCloudID
    }

    private let resolver = CloudIdentifierResolver()

    /// 動画をカメラロールに保存し、cloudIdentifier を返す
    func save(videoAt url: URL) async throws -> String {
        var savedLocalID: String?

        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .video, fileURL: url, options: nil)
            savedLocalID = request.placeholderForCreatedAsset?.localIdentifier
        }

        guard let localID = savedLocalID else {
            throw SaveError.noIdentifier
        }

        // 保存直後は cloudID がまだ取れないのでリトライ
        for attempt in 0..<10 {
            do {
                return try await resolver.cloudID(fromLocal: localID)
            } catch {
                if attempt < 9 {
                    try await Task.sleep(for: .seconds(1))
                }
            }
        }
        throw SaveError.noCloudID
    }
}
