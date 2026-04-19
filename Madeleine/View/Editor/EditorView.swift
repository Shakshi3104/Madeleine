//
//  EditorView.swift
//  Madeleine
//
//  Created by satoshikobayashi on 2026/04/19.
//

import SwiftUI
import SwiftData

struct EditorView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: EditorViewModel

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
            onMove: { source, destination in
                viewModel.moveClips(from: source, to: destination)
            },
            onDelete: { clip in
                viewModel.deleteClip(clip, modelContext: modelContext)
            }
        )
        .navigationTitle(viewModel.project.title)
        .overlay(alignment: .bottom) {
            toolBar
                .padding(.bottom)
        }
        .sheet(isPresented: $viewModel.showPreview) {
            if let url = viewModel.previewURL {
                PreviewView(url: url)
            }
        }
        .sheet(isPresented: $viewModel.showExportProgress) {
            ExportProgressView(
                progress: viewModel.exportProgress,
                isComplete: viewModel.exportProgress >= 1.0,
                onDone: { viewModel.showExportProgress = false }
            )
        }
        .sheet(isPresented: $viewModel.showShareSheet) {
            if let url = viewModel.exportedFileURL {
                ShareSheet(url: url)
            }
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

    // MARK: - Toolbar

    private var toolBar: some View {
        GlassEffectContainer {
            HStack(spacing: 16) {
                Button {
                    Task { await viewModel.generatePreview() }
                } label: {
                    Image(systemName: "play.fill")
                        .frame(width: 44, height: 44)
                }
                .disabled(viewModel.sortedClips.isEmpty)
                .glassEffect()
                .glassEffectID("play", in: glassNS)

                Button {
                    Task { await viewModel.exportAndShare() }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .frame(width: 44, height: 44)
                }
                .disabled(viewModel.sortedClips.isEmpty || viewModel.isExporting)
                .glassEffect()
                .glassEffectID("export", in: glassNS)
            }
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
