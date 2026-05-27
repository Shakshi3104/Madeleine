//
//  AutoCurator.swift
//  Madeleine
//
//  Created by Mac mini M2 Pro on 2026/05/26.
//

import Foundation
import Photos
import Vision

actor AutoCurator {
    struct CuratedClip: Sendable {
        let sourceCloudID: String
        let order: Int
    }

    struct Progress: Sendable {
        let stage: Stage
        let percent: Double
    }

    enum Stage: Sendable {
        case fetching, clustering, scoring, selecting
    }

    enum CurationError: Error {
        case noAssetsFound
        case evaluationFailed
        case noResults
    }

    private let clusterer = SceneClusterer()
    private let scorer = ImageQualityScorer()
    private let maxConcurrent = 4
    private let duplicateThreshold: Double = 0.6

    func curate(
        from: Date,
        to: Date,
        targetCount: Int,
        progress: (@Sendable (Progress) -> Void)? = nil
    ) async throws -> [CuratedClip] {
        progress?(Progress(stage: .fetching, percent: 0))
        let assets = fetchLivePhotos(from: from, to: to)
        guard !assets.isEmpty else { throw CurationError.noAssetsFound }

        try Task.checkCancellation()
        progress?(Progress(stage: .clustering, percent: 0.05))
        let scenes = clusterer.cluster(assets)

        try Task.checkCancellation()
        let scored = try await scoreAll(assets: assets, progress: progress)
        guard !scored.isEmpty else { throw CurationError.evaluationFailed }

        try Task.checkCancellation()
        progress?(Progress(stage: .selecting, percent: 0.9))
        let picked = select(scored: scored, scenes: scenes, targetCount: targetCount)
        guard !picked.isEmpty else { throw CurationError.noResults }
        progress?(Progress(stage: .selecting, percent: 1.0))

        let timeOrdered = picked.sorted {
            ($0.0.creationDate ?? .distantPast) < ($1.0.creationDate ?? .distantPast)
        }
        return timeOrdered.enumerated().map { idx, item in
            CuratedClip(sourceCloudID: item.0.localIdentifier, order: idx)
        }
    }

    func count(from: Date, to: Date) -> Int {
        PHAsset.fetchAssets(with: .image, options: Self.fetchOptions(from: from, to: to)).count
    }

    private func fetchLivePhotos(from: Date, to: Date) -> [PHAsset] {
        let result = PHAsset.fetchAssets(with: .image, options: Self.fetchOptions(from: from, to: to))
        var assets: [PHAsset] = []
        result.enumerateObjects { asset, _, _ in
            assets.append(asset)
        }
        return assets
    }

    private static func fetchOptions(from: Date, to: Date) -> PHFetchOptions {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(
            format: "(mediaSubtypes & %d) != 0 AND creationDate >= %@ AND creationDate <= %@",
            PHAssetMediaSubtype.photoLive.rawValue,
            from as NSDate,
            to as NSDate
        )
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        return options
    }

    private func scoreAll(
        assets: [PHAsset],
        progress: (@Sendable (Progress) -> Void)?
    ) async throws -> [(PHAsset, ImageQualityScorer.Score)] {
        let total = assets.count
        var processed = 0
        var results: [(PHAsset, ImageQualityScorer.Score)] = []

        try await withThrowingTaskGroup(of: (PHAsset, ImageQualityScorer.Score)?.self) { [scorer, maxConcurrent] group in
            var iterator = assets.makeIterator()

            for _ in 0..<maxConcurrent {
                guard let asset = iterator.next() else { break }
                group.addTask {
                    let score = try? await scorer.score(asset)
                    return score.map { (asset, $0) }
                }
            }

            while let next = try await group.next() {
                processed += 1
                if let next { results.append(next) }
                let percent = 0.1 + 0.8 * (Double(processed) / Double(max(total, 1)))
                progress?(Progress(stage: .scoring, percent: percent))

                if let asset = iterator.next() {
                    group.addTask {
                        let score = try? await scorer.score(asset)
                        return score.map { (asset, $0) }
                    }
                }
            }
        }
        return results
    }

    private func select(
        scored: [(PHAsset, ImageQualityScorer.Score)],
        scenes: [[PHAsset]],
        targetCount: Int
    ) -> [(PHAsset, ImageQualityScorer.Score)] {
        var sceneIdxByAsset: [String: Int] = [:]
        for (sceneIdx, scene) in scenes.enumerated() {
            for asset in scene {
                sceneIdxByAsset[asset.localIdentifier] = sceneIdx
            }
        }

        var grouped: [[(PHAsset, ImageQualityScorer.Score)]] = Array(repeating: [], count: scenes.count)
        for (asset, score) in scored where !score.isUtility {
            guard let idx = sceneIdxByAsset[asset.localIdentifier] else { continue }
            grouped[idx].append((asset, score))
        }
        var sceneQueues = grouped
            .map { $0.sorted { $0.1.aesthetic > $1.1.aesthetic } }
            .filter { !$0.isEmpty }
        if sceneQueues.isEmpty { return [] }

        var picked: [(PHAsset, ImageQualityScorer.Score)] = []
        let maxRounds = (targetCount + sceneQueues.count - 1) / sceneQueues.count + 1

        for _ in 0..<maxRounds {
            for sceneIdx in 0..<sceneQueues.count {
                if picked.count >= targetCount { return picked }
                while !sceneQueues[sceneIdx].isEmpty {
                    let candidate = sceneQueues[sceneIdx].removeFirst()
                    if !isDuplicate(candidate.1, against: picked.map { $0.1 }) {
                        picked.append(candidate)
                        break
                    }
                }
            }
            if sceneQueues.allSatisfy({ $0.isEmpty }) { break }
        }
        return picked
    }

    private func isDuplicate(
        _ candidate: ImageQualityScorer.Score,
        against existing: [ImageQualityScorer.Score]
    ) -> Bool {
        guard let cFP = candidate.featurePrint else { return false }
        for e in existing {
            guard let eFP = e.featurePrint else { continue }
            if let distance = try? cFP.distance(to: eFP), distance < duplicateThreshold {
                return true
            }
        }
        return false
    }
}
