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
            }
        )
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Button {
                    editingTitle = viewModel.project.title
                    isEditingTitle = true
                } label: {
                    Text(viewModel.project.title)
                        .font(.headline)
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
            .glassEffect(.regular.interactive())
            .glassEffectID("share", in: glassNS)

            Spacer()

            // 中央: プレビュー + 縦横切替（1つのガラスグループ）
            HStack(spacing: 24) {
                Button {
                    Task { await viewModel.generatePreview() }
                } label: {
                    Image(systemName: "play.fill")
                        .font(.title2)
                        .frame(width: 56, height: 56)
                }
                .disabled(viewModel.sortedClips.isEmpty)

                Menu {
                    Picker("Orientation", selection: $viewModel.orientation) {
                        ForEach(VideoOrientation.allCases, id: \.self) { orientation in
                            Label(orientation.rawValue, systemImage: orientation.systemImage)
                        }
                    }
                } label: {
                    Image(systemName: viewModel.orientation.systemImage)
                        .font(.title2)
                        .frame(width: 56, height: 56)
                }
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

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
