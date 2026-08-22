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
            // 素材が複数の日付にまたがるときだけ、時刻の上に日付を小さく添える
            let days = Set(timestampSegments.map { Calendar.current.startOfDay(for: $0.captureDate) })
            let showsDate = days.count > 1

            videoComp.animationTool = makeTimestampAnimationTool(
                segments: merging(timestampSegments, showsDate: showsDate),
                renderSize: renderSize,
                showsDate: showsDate
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

    /// 固定フォーマットなので、和暦などのカレンダー設定に引きずられないよう en_US_POSIX で固定する
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        // 1本の vlog が年を跨ぐことはない前提で、月日のみ
        formatter.dateFormat = "MM.dd"
        return formatter
    }()

    /// 表示文字列が同じまま連続する区間をひとつにまとめる。
    ///
    /// 既定では時刻（HH:mm）しか出さないので、同じ分に撮った連続クリップは同一表示になる。
    /// 分けたままだとクリップの切り替わりで一瞬点滅しうるうえ、レイヤも無駄に増える。
    private func merging(_ segments: [TimestampSegment], showsDate: Bool) -> [TimestampSegment] {
        var merged: [TimestampSegment] = []

        for segment in segments {
            guard let previous = merged.last,
                  label(for: previous.captureDate, showsDate: showsDate)
                      == label(for: segment.captureDate, showsDate: showsDate),
                  // 撮影日時のないクリップを挟んだ場合は連続していないので束ねない
                  CMTimeAdd(previous.start, previous.duration) == segment.start
            else {
                merged.append(segment)
                continue
            }

            merged[merged.count - 1] = TimestampSegment(
                start: previous.start,
                duration: CMTimeAdd(previous.duration, segment.duration),
                captureDate: previous.captureDate
            )
        }

        return merged
    }

    private func label(for date: Date, showsDate: Bool) -> String {
        let time = Self.timeFormatter.string(from: date)
        return showsDate ? "\(Self.dateFormatter.string(from: date))\n\(time)" : time
    }

    /// 各クリップの撮影時刻を焼き込む CoreAnimation ツールを組み立てる。
    ///
    /// - Portrait: 水平中央、垂直はやや上寄り
    /// - Landscape: 左寄せ、垂直中央
    ///
    /// CoreAnimation の座標系は原点が左下なので、Y は下端からの距離で指定する。
    private func makeTimestampAnimationTool(
        segments: [TimestampSegment],
        renderSize: CGSize,
        showsDate: Bool
    ) -> AVVideoCompositionCoreAnimationTool {
        let parentLayer = CALayer()
        let videoLayer = CALayer()
        parentLayer.frame = CGRect(origin: .zero, size: renderSize)
        videoLayer.frame = CGRect(origin: .zero, size: renderSize)
        parentLayer.addSublayer(videoLayer)

        // 縦横どちらでも読みやすいよう、短辺を基準にサイズを決める
        let isPortrait = renderSize.height >= renderSize.width
        let shortSide = min(renderSize.width, renderSize.height)
        let timeFontSize = shortSide * 0.14
        let dateFontSize = timeFontSize * 0.36
        let lineSpacing = timeFontSize * 0.01
        let sidePadding = shortSide * 0.06

        // CATextLayer は箱の上端から字を描くので、日付の箱を詰めるほど時刻に寄る
        let timeLineHeight = timeFontSize * 1.2
        let dateLineHeight = dateFontSize * 1.15
        let blockHeight = showsDate ? dateLineHeight + lineSpacing + timeLineHeight : timeLineHeight

        // Portrait はやや上寄せ、Landscape はきっちり垂直中央
        let blockCenterY = renderSize.height * (isPortrait ? 0.54 : 0.5)

        for segment in segments {
            let container = CALayer()
            container.frame = CGRect(
                x: 0,
                y: blockCenterY - blockHeight / 2,
                width: renderSize.width,
                height: blockHeight
            )

            let timeText = attributed(
                Self.timeFormatter.string(from: segment.captureDate),
                fontSize: timeFontSize,
                weight: .bold
            )
            let timeMetrics = metrics(of: timeText)

            // 時刻の字面の左端。Portrait は字面基準で中央に、Landscape は左端に置く。
            // 送り幅で中央化すると、1 のように送り枠内で細い数字が来たとき中心がずれる
            let glyphOriginX = isPortrait
                ? (renderSize.width - timeMetrics.glyphWidth) / 2
                : sidePadding

            // 原点が左下なので、時刻がコンテナ下端・日付がその上に載る
            let timeLayer = makeTextLayer(timeText, shortSide: shortSide)
            timeLayer.frame = CGRect(
                x: glyphOriginX - timeMetrics.glyphLeft,
                y: 0,
                width: timeMetrics.advance + timeFontSize,
                height: timeLineHeight
            )
            container.addSublayer(timeLayer)

            if showsDate {
                let dateText = attributed(
                    Self.dateFormatter.string(from: segment.captureDate),
                    fontSize: dateFontSize,
                    weight: .semibold
                )
                let dateMetrics = metrics(of: dateText)

                let dateLayer = makeTextLayer(dateText, shortSide: shortSide)
                // 字面の左端を時刻に合わせる。左サイドベアリングはフォントサイズに
                // 比例するので、レイヤの x を揃えるだけでは数 pt ずれる
                dateLayer.frame = CGRect(
                    x: glyphOriginX - dateMetrics.glyphLeft,
                    y: timeLineHeight + lineSpacing,
                    width: dateMetrics.advance + dateFontSize,
                    height: dateLineHeight
                )
                container.addSublayer(dateLayer)
            }

            // 該当区間だけ不透明にする（fillMode は既定の .removed なので区間外は 0 に戻る）
            container.opacity = 0
            let start = CMTimeGetSeconds(segment.start)
            let show = CABasicAnimation(keyPath: "opacity")
            show.fromValue = 1
            show.toValue = 1
            show.beginTime = start <= 0 ? AVCoreAnimationBeginTimeAtZero : start
            show.duration = CMTimeGetSeconds(segment.duration)
            show.isRemovedOnCompletion = false
            container.add(show, forKey: "timestampVisibility")

            parentLayer.addSublayer(container)
        }

        return AVVideoCompositionCoreAnimationTool(
            postProcessingAsVideoLayer: videoLayer,
            in: parentLayer
        )
    }

    /// 字面の実寸。送り幅（advance）と、字面の左端・幅（image bounds）を持つ
    private struct TextMetrics {
        let advance: CGFloat
        let glyphLeft: CGFloat
        let glyphWidth: CGFloat
    }

    private func metrics(of text: NSAttributedString) -> TextMetrics {
        let line = CTLineCreateWithAttributedString(text)
        let imageBounds = CTLineGetImageBounds(line, nil)
        return TextMetrics(
            advance: CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)),
            glyphLeft: imageBounds.origin.x,
            glyphWidth: imageBounds.width
        )
    }

    private func attributed(
        _ text: String,
        fontSize: CGFloat,
        weight: UIFont.Weight
    ) -> NSAttributedString {
        NSAttributedString(
            string: text,
            attributes: [
                .font: roundedFont(ofSize: fontSize, weight: weight),
                .foregroundColor: UIColor.white
            ]
        )
    }

    /// 位置は呼び出し側が字面基準で決めるので、レイヤ内は常に左寄せで描く
    private func makeTextLayer(_ text: NSAttributedString, shortSide: CGFloat) -> CATextLayer {
        let layer = CATextLayer()
        layer.string = text
        layer.alignmentMode = .left
        layer.truncationMode = .none
        layer.isWrapped = false
        layer.contentsScale = 1
        // 明るい写真の上でも白文字が沈まないよう影を付ける
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.5
        layer.shadowRadius = shortSide * 0.006
        layer.shadowOffset = .zero
        return layer
    }

    /// SF Rounded の等幅数字フォント。
    ///
    /// `monospacedDigitSystemFont` には rounded 版がないので、systemFont に
    /// `.rounded` デザインを当てたうえで等幅数字のフィーチャを付け直している。
    /// 等幅にしないと `1` を含む時刻だけ横幅が縮んで、クリップごとに位置が揺れる。
    private func roundedFont(ofSize size: CGFloat, weight: UIFont.Weight) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        guard let rounded = base.fontDescriptor.withDesign(.rounded) else { return base }

        let monospacedDigits = rounded.addingAttributes([
            .featureSettings: [[
                UIFontDescriptor.FeatureKey.type: kNumberSpacingType,
                UIFontDescriptor.FeatureKey.selector: kMonospacedNumbersSelector
            ]]
        ])
        return UIFont(descriptor: monospacedDigits, size: size)
    }
}
