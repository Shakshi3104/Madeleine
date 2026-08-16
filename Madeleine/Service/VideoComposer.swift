//
//  VideoComposer.swift
//  Madeleine
//
//  Created by satoshikobayashi on 2026/04/19.
//

import AVFoundation
import UIKit

struct VideoComposer {
    enum ComposerError: Error {
        case trackCreationFailed
        case noClipsToCompose
    }

    /// タイムスタンプ焼き込み用に、各クリップの表示範囲と撮影日時を保持する
    private struct TimestampSegment {
        let start: CMTime
        let duration: CMTime
        let captureDate: Date
    }

    @available(iOS, deprecated: 26.0)
    func compose(
        clips: [VlogClip],
        videoURLs: [UUID: URL],
        renderSize: CGSize = CGSize(width: 1080, height: 1920),
        showsTimestamp: Bool = false
    ) async throws -> (AVComposition, AVVideoComposition) {
        let composition = AVMutableComposition()
        guard let compositionVideoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else { throw ComposerError.trackCreationFailed }

        var instructions: [AVMutableVideoCompositionInstruction] = []
        var timestampSegments: [TimestampSegment] = []
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

            if showsTimestamp, let captureDate = clip.captureDate {
                timestampSegments.append(
                    TimestampSegment(start: cursor, duration: clipLen, captureDate: captureDate)
                )
            }

            cursor = CMTimeAdd(cursor, clipLen)
        }

        guard !instructions.isEmpty else { throw ComposerError.noClipsToCompose }

        let videoComp = AVMutableVideoComposition()
        videoComp.renderSize = renderSize
        videoComp.frameDuration = CMTime(value: 1, timescale: 30)
        videoComp.instructions = instructions

        if showsTimestamp, !timestampSegments.isEmpty {
            videoComp.animationTool = makeTimestampAnimationTool(
                segments: timestampSegments,
                renderSize: renderSize
            )
        }

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

    // MARK: - Timestamp Overlay

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd HH:mm"
        return formatter
    }()

    /// setlog 風に、各クリップの撮影日時を右下へ焼き込む CoreAnimation ツールを組み立てる。
    ///
    /// CoreAnimation の座標系は原点が左下なので、Y はコンテンツ座標を反転して配置する。
    private func makeTimestampAnimationTool(
        segments: [TimestampSegment],
        renderSize: CGSize
    ) -> AVVideoCompositionCoreAnimationTool {
        let parentLayer = CALayer()
        let videoLayer = CALayer()
        parentLayer.frame = CGRect(origin: .zero, size: renderSize)
        videoLayer.frame = CGRect(origin: .zero, size: renderSize)
        parentLayer.addSublayer(videoLayer)

        // 縦横どちらでも読みやすいよう、短辺を基準にサイズを決める
        let shortSide = min(renderSize.width, renderSize.height)
        let fontSize = shortSide * 0.045
        let padding = shortSide * 0.05
        let textHeight = fontSize * 1.4
        let textWidth = renderSize.width - padding * 2

        for segment in segments {
            let textLayer = CATextLayer()
            textLayer.string = attributedTimestamp(
                Self.timestampFormatter.string(from: segment.captureDate),
                fontSize: fontSize
            )
            textLayer.alignmentMode = .right
            textLayer.truncationMode = .none
            textLayer.isWrapped = false
            textLayer.contentsScale = 1
            textLayer.frame = CGRect(
                x: padding,
                y: padding,
                width: textWidth,
                height: textHeight
            )
            // 明るい写真の上でも読めるよう影を付ける
            textLayer.shadowColor = UIColor.black.cgColor
            textLayer.shadowOpacity = 0.7
            textLayer.shadowRadius = shortSide * 0.004
            textLayer.shadowOffset = .zero

            // 該当クリップの表示区間だけ不透明にする
            textLayer.opacity = 0
            let start = CMTimeGetSeconds(segment.start)
            let show = CABasicAnimation(keyPath: "opacity")
            show.fromValue = 1
            show.toValue = 1
            show.beginTime = start <= 0 ? AVCoreAnimationBeginTimeAtZero : start
            show.duration = CMTimeGetSeconds(segment.duration)
            show.isRemovedOnCompletion = false
            textLayer.add(show, forKey: "timestampVisibility")

            parentLayer.addSublayer(textLayer)
        }

        return AVVideoCompositionCoreAnimationTool(
            postProcessingAsVideoLayer: videoLayer,
            in: parentLayer
        )
    }

    private func attributedTimestamp(_ text: String, fontSize: CGFloat) -> NSAttributedString {
        // アクセントカラー（Golden Orange #F5A623）でデジタル時計風に
        let accent = UIColor(red: 0xF5 / 255, green: 0xA6 / 255, blue: 0x23 / 255, alpha: 1)
        let font = UIFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .semibold)
        return NSAttributedString(
            string: text,
            attributes: [
                .font: font,
                .foregroundColor: accent
            ]
        )
    }
}
