//
//  SceneClusterer.swift
//  Madeleine
//
//  Created by Mac mini M2 Pro on 2026/05/26.
//

import Foundation
import Photos
import CoreLocation

struct SceneClusterer {
    var timeGapThreshold: TimeInterval = 15 * 60
    var distanceThreshold: CLLocationDistance = 100

    func cluster(_ assets: [PHAsset]) -> [[PHAsset]] {
        let sorted = assets.sorted {
            ($0.creationDate ?? .distantPast) < ($1.creationDate ?? .distantPast)
        }

        var scenes: [[PHAsset]] = []
        var current: [PHAsset] = []

        for asset in sorted {
            if let last = current.last, shouldSplit(from: last, to: asset) {
                scenes.append(current)
                current = []
            }
            current.append(asset)
        }
        if !current.isEmpty {
            scenes.append(current)
        }
        return scenes
    }

    private func shouldSplit(from a: PHAsset, to b: PHAsset) -> Bool {
        if let dA = a.creationDate, let dB = b.creationDate,
           dB.timeIntervalSince(dA) > timeGapThreshold {
            return true
        }
        if let lA = a.location, let lB = b.location,
           lA.distance(from: lB) > distanceThreshold {
            return true
        }
        return false
    }
}
