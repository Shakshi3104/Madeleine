//
//  VideoComposer.swift
//  Madeleine
//
//  Created by satoshikobayashi on 2026/04/19.
//

import AVFoundation

struct VideoComposer {
    enum ComposerError: Error {
        case trackCreationFailed
        case noClipsToCompose
    }

    @available(iOS, deprecated: 26.0)
    func compose(
        clips: [VlogClip],
        videoURLs: [UUID: URL],
        renderSize: CGSize = CGSize(width: 1080, height: 1920)
    ) async throws -> (AVComposition, AVVideoComposition) {
        let composition = AVMutableComposition()
        guard let compositionVideoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else { throw ComposerError.trackCreationFailed }

        var instructions: [AVMutableVideoCompositionInstruction] = []
        var cursor = CMTime.zero
        let sortedClips = clips.sorted { $0.order < $1.order }

        for clip in sortedClips {
            guard let url = videoURLs[clip.id] else {
                print("⚠️ No URL for clip \(clip.id)")
                continue
            }
            let asset = AVURLAsset(url: url)
            let srcVideoTracks = try await asset.loadTracks(withMediaType: .video)
            guard let srcVideo = srcVideoTracks.first else {
                print("⚠️ No video track in \(url.lastPathComponent)")
                continue
            }

            let duration = try await asset.load(.duration)
            let durationSeconds = CMTimeGetSeconds(duration)
            let trimSeconds = min(clip.trimDuration, durationSeconds)
            let clipLen = CMTime(seconds: trimSeconds, preferredTimescale: 600)

            let startTime: CMTime
            if let ts = clip.trimStart {
                startTime = CMTime(seconds: min(ts, max(0, durationSeconds - trimSeconds)), preferredTimescale: 600)
            } else {
                // 中央から切り出し（負の値にならないようクランプ）
                let centerSeconds = max(0, (durationSeconds - trimSeconds) / 2.0)
                startTime = CMTime(seconds: centerSeconds, preferredTimescale: 600)
            }
            let range = CMTimeRange(start: startTime, duration: clipLen)

            print("🎬 clip \(clip.order): duration=\(durationSeconds)s, trim=\(trimSeconds)s, start=\(CMTimeGetSeconds(startTime))s")

            try compositionVideoTrack.insertTimeRange(range, of: srcVideo, at: cursor)

            // preferredTransform を適用して向きを正す
            let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionVideoTrack)
            let transform = try await computeTransform(for: srcVideo, renderSize: renderSize)
            layerInstruction.setTransform(transform, at: cursor)

            let instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = CMTimeRange(start: cursor, duration: clipLen)
            instruction.layerInstructions = [layerInstruction]
            instructions.append(instruction)

            cursor = CMTimeAdd(cursor, clipLen)
        }

        guard !instructions.isEmpty else { throw ComposerError.noClipsToCompose }

        let videoComp = AVMutableVideoComposition()
        videoComp.renderSize = renderSize
        videoComp.frameDuration = CMTime(value: 1, timescale: 30)
        videoComp.instructions = instructions

        print("🎬 Composition total duration: \(CMTimeGetSeconds(cursor))s, \(instructions.count) instructions")

        return (composition, videoComp)
    }

    private func computeTransform(
        for track: AVAssetTrack,
        renderSize: CGSize
    ) async throws -> CGAffineTransform {
        let naturalSize = try await track.load(.naturalSize)
        let preferred = try await track.load(.preferredTransform)

        // preferredTransform を適用した後の実際の表示サイズ
        let transformed = CGRect(origin: .zero, size: naturalSize).applying(preferred)
        let displaySize = CGSize(
            width: abs(transformed.width),
            height: abs(transformed.height)
        )

        // aspect fill: renderSize を完全に覆うスケール
        let scale = max(
            renderSize.width / displaySize.width,
            renderSize.height / displaySize.height
        )

        // 1. 原点に正規化（preferredTransform の平行移動成分を除去）
        let normalizeTranslation = CGAffineTransform(
            translationX: -transformed.origin.x,
            y: -transformed.origin.y
        )

        // 2. スケーリング
        let scaleTransform = CGAffineTransform(scaleX: scale, y: scale)

        // 3. 中央配置
        let scaledWidth = displaySize.width * scale
        let scaledHeight = displaySize.height * scale
        let centerTranslation = CGAffineTransform(
            translationX: (renderSize.width - scaledWidth) / 2,
            y: (renderSize.height - scaledHeight) / 2
        )

        return preferred
            .concatenating(normalizeTranslation)
            .concatenating(scaleTransform)
            .concatenating(centerTranslation)
    }
}
