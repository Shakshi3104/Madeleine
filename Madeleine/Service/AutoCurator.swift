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
        dates: [Date],
        targetCount: Int,
        progress: (@Sendable (Progress) -> Void)? = nil
    ) async throws -> [CuratedClip] {
        progress?(Progress(stage: .fetching, percent: 0))
        let assets = fetchLivePhotos(dates: dates)
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

    func count(dates: [Date]) -> Int {
        guard !dates.isEmpty else { return 0 }
        return PHAsset.fetchAssets(with: .image, options: Self.fetchOptions(dates: dates)).count
    }

    private func fetchLivePhotos(dates: [Date]) -> [PHAsset] {
        guard !dates.isEmpty else { return [] }
        let result = PHAsset.fetchAssets(with: .image, options: Self.fetchOptions(dates: dates))
        var assets: [PHAsset] = []
        result.enumerateObjects { asset, _, _ in
            assets.append(asset)
        }
        return assets
    }

    private static func fetchOptions(dates: [Date]) -> PHFetchOptions {
        let cal = Calendar.current
        let dayPredicates: [NSPredicate] = dates.map { day in
            let start = cal.startOfDay(for: day)
            let end = cal.date(byAdding: .day, value: 1, to: start) ?? start
            return NSPredicate(
                format: "creationDate >= %@ AND creationDate < %@",
                start as NSDate,
                end as NSDate
            )
        }
        let livePhotoPredicate = NSPredicate(
            format: "(mediaSubtypes & %d) != 0",
            PHAssetMediaSubtype.photoLive.rawValue
        )

        let options = PHFetchOptions()
        options.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            livePhotoPredicate,
            NSCompoundPredicate(orPredicateWithSubpredicates: dayPredicates)
        ])
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
        let sceneQueues = grouped
            .map { $0.sorted { $0.1.aesthetic > $1.1.aesthetic } }
            .filter { !$0.isEmpty }
        if sceneQueues.isEmpty { return [] }

        let quotas = proportionalQuotas(
            sceneSizes: sceneQueues.map { $0.count },
            targetCount: targetCount
        )

        var picked: [(PHAsset, ImageQualityScorer.Score)] = []
        for (sceneIdx, scene) in sceneQueues.enumerated() {
            var taken = 0
            for candidate in scene {
                if taken >= quotas[sceneIdx] || picked.count >= targetCount { break }
                if !isDuplicate(candidate.1, against: picked.map { $0.1 }) {
                    picked.append(candidate)
                    taken += 1
                }
            }
        }

        // quota の丸めや重複排除で目標に届かなければ、残った候補から
        // 美的スコア順で詰める
        if picked.count < targetCount {
            let pickedIDs = Set(picked.map { $0.1.assetID })
            let leftovers = sceneQueues
                .flatMap { $0 }
                .filter { !pickedIDs.contains($0.1.assetID) }
                .sorted { $0.1.aesthetic > $1.1.aesthetic }
            for candidate in leftovers {
                if picked.count >= targetCount { break }
                if !isDuplicate(candidate.1, against: picked.map { $0.1 }) {
                    picked.append(candidate)
                }
            }
        }
        return picked
    }

    /// シーンごとの枠数を写真数に比例配分する。シーン数 ≤ targetCount のときは
    /// 「どのシーンからも最低 1 枚」を保証 (= 偏った旅行でも全シーンに代表が
    /// 残る)。シーン数 > targetCount のときは 0 を許容して小さいシーンを落とす。
    /// シーン内の写真数を超えて配分することはない。
    private func proportionalQuotas(sceneSizes: [Int], targetCount: Int) -> [Int] {
        let totalAssets = sceneSizes.reduce(0, +)
        guard totalAssets > 0 else { return Array(repeating: 0, count: sceneSizes.count) }
        let allowZero = sceneSizes.count > targetCount

        return sceneSizes.map { size in
            let proportional = Double(targetCount) * Double(size) / Double(totalAssets)
            let base = allowZero ? Int(proportional.rounded()) : max(1, Int(proportional.rounded()))
            return min(size, base)
        }
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
