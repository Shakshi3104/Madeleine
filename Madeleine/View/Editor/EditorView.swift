//
//  EditorView.swift
//  Madeleine
//
//  Created by satoshikobayashi on 2026/04/19.
//

import SwiftUI
import SwiftData
import PhotosUI
import Photos

struct EditorView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: EditorViewModel
    @State private var isEditingTitle = false
    @State private var editingTitle = ""
    @State private var isReordering = false
    @State private var showInfo = false
    @State private var previewingClip: VlogClip?
    @State private var additionalPhotos: [PhotosPickerItem] = []

    @Namespace private var glassNS

    init(project: VlogProject, extractedURLs: [UUID: URL]) {
        _viewModel = State(initialValue: EditorViewModel(
            project: project,
            extractedURLs: extractedURLs
        ))
    }

    var body: some View {
        ClipTimelineView(
            clips: viewModel.sortedClips,
            extractedURLs: viewModel.extractedURLs,
            isReordering: $isReordering,
            onMove: { source, destination in
                viewModel.moveClips(from: source, to: destination)
            },
            onDelete: { clip in
                viewModel.deleteClip(clip, modelContext: modelContext)
            },
            onTap: { clip in
                guard !isReordering else { return }
                previewingClip = clip
            }
        )
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Button {
                    editingTitle = viewModel.project.title
                    isEditingTitle = true
                } label: {
                    titleLabel
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    isReordering.toggle()
                } label: {
                    Image(systemName: isReordering ? "checkmark" : "arrow.up.arrow.down")
                }
            }
        }
        .overlay(alignment: .bottom) {
            bottomBar
        }
        .sheet(isPresented: $viewModel.showPreview) {
            if let url = viewModel.previewURL {
                PreviewView(url: url)
            }
        }
        .sheet(isPresented: $viewModel.showShareSheet) {
            if let url = viewModel.exportedFileURL {
                ShareSheet(url: url)
            }
        }
        .sheet(isPresented: $showInfo) {
            ProjectInfoSheet(
                project: viewModel.project,
                clipCount: viewModel.sortedClips.count,
                totalDuration: viewModel.sortedClips.reduce(0) { $0 + $1.trimDuration },
                orientation: viewModel.orientation
            )
        }
        .sheet(item: $previewingClip) { clip in
            ClipCropPreviewSheet(clip: clip, initialOrientation: viewModel.orientation)
        }
        .overlay {
            if viewModel.isGeneratingPreview || viewModel.isExporting || viewModel.isAddingClips {
                ZStack {
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()
                    VStack(spacing: 16) {
                        ProgressView()
                            .controlSize(.large)
                        Text(viewModel.loadingMessage)
                            .font(.subheadline)
                            .foregroundStyle(.white)
                    }
                }
            }
        }
        .alert("Rename Vlog", isPresented: $isEditingTitle) {
            TextField("Title", text: $editingTitle)
            Button("OK") {
                viewModel.project.title = editingTitle
                viewModel.project.updatedAt = .now
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert(
            "Error",
            isPresented: .init(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )
        ) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    // MARK: - Title

    private var titleLabel: some View {
        Text(viewModel.project.title)
            .font(.headline)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: 220)
    }

    // MARK: - Bottom Bar (Photos app style)

    private var bottomBar: some View {
        HStack {
            // 左: シェアボタン
            Button {
                Task { await viewModel.exportAndShare() }
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.title2)
                    .frame(width: 56, height: 56)
            }
            .disabled(viewModel.sortedClips.isEmpty || viewModel.isExporting)
            .accessibilityLabel("Share")
            .glassEffect(.regular.interactive())
            .glassEffectID("share", in: glassNS)

            Spacer()

            // 中央: プレビュー + 縦横切替 + インフォ（1つのガラスグループ）
            HStack(spacing: 16) {
                Button {
                    Task { await viewModel.generatePreview() }
                } label: {
                    Image(systemName: "play.fill")
                        .font(.title2)
                        .frame(width: 56, height: 56)
                }
                .disabled(viewModel.sortedClips.isEmpty)
                .accessibilityLabel("Preview")

                Menu {
                    Picker("Orientation", selection: Binding(
                        get: { viewModel.orientation },
                        set: { viewModel.updateOrientation($0) }
                    )) {
                        ForEach(VideoOrientation.allCases, id: \.self) { orientation in
                            Label(orientation.displayName, systemImage: orientation.systemImage)
                        }
                    }
                } label: {
                    Image(systemName: viewModel.orientation.systemImage)
                        .font(.title2)
                        .frame(width: 56, height: 56)
                }
                .accessibilityLabel("Orientation")

                Button {
                    showInfo = true
                } label: {
                    Image(systemName: "info.circle")
                        .font(.title2)
                        .frame(width: 56, height: 56)
                }
                .accessibilityLabel("Info")
            }
            .padding(.horizontal, 6)
            .glassEffect()
            .glassEffectID("center", in: glassNS)

            Spacer()

            // 右: Live Photo 追加
            PhotosPicker(
                selection: $additionalPhotos,
                maxSelectionCount: 30,
                matching: .livePhotos,
                photoLibrary: .shared()
            ) {
                Image(systemName: "plus")
                    .font(.title2)
                    .foregroundStyle(.primary)
                    .frame(width: 56, height: 56)
            }
            .accessibilityLabel("Add Live Photos")
            .glassEffect(.regular.interactive())
            .glassEffectID("add", in: glassNS)
            .onChange(of: additionalPhotos) { _, newItems in
                guard !newItems.isEmpty else { return }
                Task {
                    await viewModel.addClips(from: newItems, modelContext: modelContext)
                }
                additionalPhotos = []
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
        .tint(.primary)
    }
}

// MARK: - Project Info Sheet

private struct ProjectInfoSheet: View {
    let project: VlogProject
    let clipCount: Int
    let totalDuration: Double
    let orientation: VideoOrientation

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy/MM/dd HH:mm:ss"
        return f
    }()

    private var durationText: String {
        String(format: "%.1f s", totalDuration)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Title")
                            .foregroundStyle(.secondary)
                        Text(project.title)
                    }
                    LabeledContent("Photos", value: "\(clipCount)")
                    LabeledContent("Duration", value: durationText)
                    LabeledContent("Orientation", value: orientation.displayName)
                }
                Section {
                    LabeledContent("Created", value: Self.dateFormatter.string(from: project.createdAt))
                    LabeledContent("Updated", value: Self.dateFormatter.string(from: project.updatedAt))
                }
            }
            .navigationTitle("Info")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Clip Crop Preview Sheet

private struct ClipCropPreviewSheet: View {
    let clip: VlogClip

    @State private var orientation: VideoOrientation
    @State private var image: UIImage?

    init(clip: VlogClip, initialOrientation: VideoOrientation) {
        self.clip = clip
        _orientation = State(initialValue: initialOrientation)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            GeometryReader { proxy in
                if let image {
                    cropOverlay(image: image, in: proxy.size)
                } else {
                    ProgressView()
                        .controlSize(.large)
                        .tint(.white)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }

            VStack {
                orientationToggle
                    .padding(.top, 12)
                Spacer()
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .task {
            await loadImage()
        }
    }

    private var orientationToggle: some View {
        HStack(spacing: 8) {
            ForEach(VideoOrientation.allCases, id: \.self) { option in
                Button {
                    orientation = option
                } label: {
                    Image(systemName: option.systemImage)
                        .font(.title3)
                        .frame(width: 56, height: 44)
                        .foregroundStyle(orientation == option ? Color.accentColor : .primary)
                }
                .accessibilityLabel(option.displayName)
            }
        }
        .padding(.horizontal, 6)
        .glassEffect()
    }

    @ViewBuilder
    private func cropOverlay(image: UIImage, in container: CGSize) -> some View {
        let imageAspect = image.size.width / max(image.size.height, 1)
        let containerAspect = container.width / max(container.height, 1)

        // Image displayed via aspect-fit
        let displaySize: CGSize = {
            if imageAspect > containerAspect {
                return CGSize(width: container.width, height: container.width / imageAspect)
            } else {
                return CGSize(width: container.height * imageAspect, height: container.height)
            }
        }()

        let outputAspect = orientation.renderSize.width / orientation.renderSize.height

        // Crop region within the displayed image (aspect-fill of output → visible region in source)
        let cropSize: CGSize = {
            if imageAspect > outputAspect {
                return CGSize(width: displaySize.height * outputAspect, height: displaySize.height)
            } else {
                return CGSize(width: displaySize.width, height: displaySize.width / outputAspect)
            }
        }()

        let center = CGPoint(x: container.width / 2, y: container.height / 2)
        let cropRect = CGRect(
            x: center.x - cropSize.width / 2,
            y: center.y - cropSize.height / 2,
            width: cropSize.width,
            height: cropSize.height
        )

        ZStack {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: displaySize.width, height: displaySize.height)
                .position(center)

            Canvas { ctx, size in
                var path = Path()
                path.addRect(CGRect(origin: .zero, size: size))
                path.addRect(cropRect)
                ctx.fill(path, with: .color(.black.opacity(0.55)), style: FillStyle(eoFill: true))
            }
            .allowsHitTesting(false)

            Rectangle()
                .strokeBorder(Color.white, lineWidth: 2)
                .frame(width: cropSize.width, height: cropSize.height)
                .position(x: cropRect.midX, y: cropRect.midY)
                .allowsHitTesting(false)
        }
    }

    private func loadImage() async {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [clip.sourceCloudID], options: nil)
        guard let asset = assets.firstObject else { return }

        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .exact

        let target = CGSize(width: 1500, height: 1500)
        let loaded: UIImage? = await withCheckedContinuation { continuation in
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: target,
                contentMode: .aspectFit,
                options: options
            ) { result, _ in
                continuation.resume(returning: result)
            }
        }
        if let loaded {
            image = loaded
        }
    }
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
