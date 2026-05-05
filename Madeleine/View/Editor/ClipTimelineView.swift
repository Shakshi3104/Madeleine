//
//  ClipTimelineView.swift
//  Madeleine
//
//  Created by satoshikobayashi on 2026/04/19.
//

import SwiftUI
import AVFoundation

struct ClipTimelineView: View {
    let clips: [VlogClip]
    let extractedURLs: [UUID: URL]
    @Binding var isReordering: Bool
    let onMove: (IndexSet, Int) -> Void
    let onDelete: (VlogClip) -> Void
    let onTap: (VlogClip) -> Void

    @State private var editMode: EditMode = .inactive

    var body: some View {
        List {
            ForEach(clips) { clip in
                Button {
                    onTap(clip)
                } label: {
                    ClipRow(clip: clip, videoURL: extractedURLs[clip.id])
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        onDelete(clip)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
            .onMove { source, destination in
                onMove(source, destination)
            }

            // ボトムバーとの被り防止
            Color.clear
                .frame(height: 80)
                .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .environment(\.editMode, $editMode)
        .onChange(of: isReordering) { _, newValue in
            editMode = newValue ? .active : .inactive
        }
        .onChange(of: editMode) { _, newValue in
            if newValue == .inactive {
                isReordering = false
            }
        }
    }
}

// MARK: - Clip Row

struct ClipRow: View {
    let clip: VlogClip
    let videoURL: URL?

    @State private var thumbnail: Image?

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy/MM/dd HH:mm:ss"
        return f
    }()

    var body: some View {
        HStack(spacing: 12) {
            // サムネイル
            Group {
                if let thumbnail {
                    thumbnail
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Rectangle()
                        .fill(.quaternary)
                        .overlay {
                            Image(systemName: "photo")
                                .foregroundStyle(.secondary)
                        }
                }
            }
            .frame(width: 60, height: 60)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // 情報
            VStack(alignment: .leading, spacing: 4) {
                Text(clip.originalFilename.isEmpty ? "Clip \(clip.order + 1)" : clip.originalFilename)
                    .font(.headline)
                    .lineLimit(1)
                if let date = clip.captureDate {
                    Text(Self.dateFormatter.string(from: date))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
        .task {
            await loadThumbnail()
        }
    }

    private func loadThumbnail() async {
        guard let url = videoURL else { return }
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 120, height: 120)

        do {
            let (cgImage, _) = try await generator.image(at: .zero)
            thumbnail = Image(decorative: cgImage, scale: 1.0)
        } catch {
            print("Thumbnail generation failed: \(error)")
        }
    }
}
