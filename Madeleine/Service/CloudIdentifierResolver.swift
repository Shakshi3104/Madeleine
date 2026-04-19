//
//  CloudIdentifierResolver.swift
//  Madeleine
//
//  Created by satoshikobayashi on 2026/04/19.
//

import Photos

actor CloudIdentifierResolver {
    enum ResolveError: Error {
        case notFound
        case permissionDenied
    }

    /// localIdentifier → cloudIdentifier（保存時）
    func cloudID(fromLocal localID: String) throws -> String {
        let mappings = PHPhotoLibrary.shared()
            .cloudIdentifierMappings(forLocalIdentifiers: [localID])
        guard let result = mappings[localID] else {
            throw ResolveError.notFound
        }
        return try result.get().stringValue
    }

    /// cloudIdentifier → PHAsset（読み込み時）
    func asset(fromCloud cloudID: String) throws -> PHAsset {
        let pcid = PHCloudIdentifier(stringValue: cloudID)
        let mappings = PHPhotoLibrary.shared()
            .localIdentifierMappings(for: [pcid])
        guard let result = mappings[pcid] else {
            throw ResolveError.notFound
        }
        let localID = try result.get()
        guard let asset = PHAsset.fetchAssets(
            withLocalIdentifiers: [localID], options: nil
        ).firstObject else {
            throw ResolveError.notFound
        }
        return asset
    }
}
