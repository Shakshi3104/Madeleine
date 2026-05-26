//
//  ImageQualityScorer.swift
//  Madeleine
//
//  Created by Mac mini M2 Pro on 2026/05/26.
//

import Foundation
import Vision
import Photos
import UIKit

actor ImageQualityScorer {
    struct Score: Sendable {
        let assetID: String
        let aesthetic: Float
        let isUtility: Bool
        let faceQuality: Float?
        let featurePrint: FeaturePrintObservation?
    }

    enum ScorerError: Error {
        case imageUnavailable
    }

    private let targetSize = CGSize(width: 512, height: 512)

    func score(_ asset: PHAsset) async throws -> Score {
        let cgImage = try await loadCGImage(for: asset)

        async let aesthetics = runAesthetics(on: cgImage)
        async let featurePrint = runFeaturePrint(on: cgImage)
        async let faceQuality = runFaceQuality(on: cgImage)

        let (aes, fp, fq) = try await (aesthetics, featurePrint, faceQuality)

        return Score(
            assetID: asset.localIdentifier,
            aesthetic: aes.overallScore,
            isUtility: aes.isUtility,
            faceQuality: fq,
            featurePrint: fp
        )
    }

    private func runAesthetics(on image: CGImage) async throws -> ImageAestheticsScoresObservation {
        let request = CalculateImageAestheticsScoresRequest()
        return try await request.perform(on: image)
    }

    private func runFeaturePrint(on image: CGImage) async throws -> FeaturePrintObservation? {
        let request = GenerateImageFeaturePrintRequest()
        return try await request.perform(on: image)
    }

    private func runFaceQuality(on image: CGImage) async throws -> Float? {
        let request = DetectFaceCaptureQualityRequest()
        let observations = try await request.perform(on: image)
        return observations.compactMap { $0.captureQuality?.score }.max()
    }

    private func loadCGImage(for asset: PHAsset) async throws -> CGImage {
        try await withCheckedThrowingContinuation { continuation in
            let options = PHImageRequestOptions()
            options.isSynchronous = false
            options.isNetworkAccessAllowed = false
            options.deliveryMode = .fastFormat
            options.resizeMode = .fast

            PHImageManager.default().requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFit,
                options: options
            ) { image, info in
                if let error = info?[PHImageErrorKey] as? Error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let cgImage = image?.cgImage else {
                    continuation.resume(throwing: ScorerError.imageUnavailable)
                    return
                }
                continuation.resume(returning: cgImage)
            }
        }
    }
}
