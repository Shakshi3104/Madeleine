//
//  ContentView.swift
//  Madeleine
//
//  Created by satoshikobayashi on 2026/04/19.
//

import SwiftUI
import SwiftData
import PhotosUI
import Photos

// MARK: - Navigation Destination

enum AppDestination: Hashable {
    case extracting(VlogProject)
    case editor(VlogProject, [UUID: URL])

    static func == (lhs: AppDestination, rhs: AppDestination) -> Bool {
        switch (lhs, rhs) {
        case let (.extracting(a), .extracting(b)):
            return a.persistentModelID == b.persistentModelID
        case let (.editor(a, _), .editor(b, _)):
            return a.persistentModelID == b.persistentModelID
        default:
            return false
        }
    }

    func hash(into hasher: inout Hasher) {
        switch self {
        case .extracting(let project):
            hasher.combine(0)
            hasher.combine(project.persistentModelID)
        case .editor(let project, _):
            hasher.combine(1)
            hasher.combine(project.persistentModelID)
        }
    }
}

// MARK: - ContentView

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \VlogProject.updatedAt, order: .reverse) private var projects: [VlogProject]

    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var navigationPath = NavigationPath()
    @State private var showAbout = false

    @Namespace private var glassNS

    var body: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                if projects.isEmpty {
                    emptyState
                } else {
                    projectList
                }
            }
            .navigationTitle("")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAbout = true
                    } label: {
                        Image(systemName: "info.circle")
                    }
                    .accessibilityLabel("About")
                }
            }
            .navigationDestination(for: AppDestination.self) { destination in
                switch destination {
                case .extracting(let project):
                    ExtractingView(project: project) { extractedURLs in
                        // 抽出完了 → EditorView へ遷移
                        navigationPath.removeLast()
                        navigationPath.append(AppDestination.editor(project, extractedURLs))
                    }
                case .editor(let project, let urls):
                    EditorView(project: project, extractedURLs: urls)
                }
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if navigationPath.isEmpty {
                newProjectButton
                    .padding()
            }
        }
        .sheet(isPresented: $showAbout) {
            AboutView()
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView(
            "No Vlogs Yet",
            systemImage: "video.badge.plus",
            description: Text("Tap + to select Live Photos and create your first vlog.")
        )
    }

    // MARK: - Project List

    private var projectList: some View {
        List {
            ForEach(projects) { project in
                Button {
                    navigationPath.append(AppDestination.extracting(project))
                } label: {
                    VlogProjectRow(project: project)
                }
                .foregroundStyle(.primary)
            }
            .onDelete(perform: deleteProjects)
        }
    }

    // MARK: - FAB

    private var newProjectButton: some View {
        GlassEffectContainer {
            PhotosPicker(
                selection: $selectedPhotos,
                maxSelectionCount: 30,
                matching: .livePhotos,
                photoLibrary: .shared()
            ) {
                Image(systemName: "plus")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(Color.accentColor)
                    .clipShape(Circle())
            }
            .accessibilityLabel("New Vlog")
            .glassEffectID("newProject", in: glassNS)
        }
        .onChange(of: selectedPhotos) { _, newItems in
            guard !newItems.isEmpty else { return }
            let project = createProject(from: newItems)
            selectedPhotos = []
            navigationPath.append(AppDestination.extracting(project))
        }
    }

    // MARK: - Actions

    @discardableResult
    private func createProject(from items: [PhotosPickerItem]) -> VlogProject {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy/MM/dd"
        let defaultTitle = "Vlog \(dateFormatter.string(from: Date()))"
        let project = VlogProject(title: defaultTitle)
        modelContext.insert(project)

        // PHAsset の情報を取得してソート用に収集
        struct ClipInfo {
            let localID: String
            let filename: String
            let captureDate: Date?
        }

        var clipInfos: [ClipInfo] = []
        for item in items {
            guard let localID = item.itemIdentifier else { continue }
            let assets = PHAsset.fetchAssets(withLocalIdentifiers: [localID], options: nil)
            let filename: String
            let captureDate: Date?
            if let asset = assets.firstObject {
                filename = PHAssetResource.assetResources(for: asset).first?.originalFilename ?? ""
                captureDate = asset.creationDate
            } else {
                filename = ""
                captureDate = nil
            }
            clipInfos.append(ClipInfo(localID: localID, filename: filename, captureDate: captureDate))
        }

        // 撮影日時が古い順にソート
        clipInfos.sort { ($0.captureDate ?? .distantFuture) < ($1.captureDate ?? .distantFuture) }

        for (index, info) in clipInfos.enumerated() {
            let clip = VlogClip(
                order: index,
                sourceCloudID: info.localID,
                originalFilename: info.filename,
                captureDate: info.captureDate
            )
            clip.project = project
            modelContext.insert(clip)
        }

        project.updatedAt = .now
        return project
    }

    private func deleteProjects(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(projects[index])
            }
        }
    }
}

// MARK: - Project Row

struct VlogProjectRow: View {
    let project: VlogProject
    @State private var thumbnail: Image?

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy/MM/dd"
        return f
    }()

    private var firstClipCloudID: String? {
        project.clips?
            .sorted { $0.order < $1.order }
            .first?
            .sourceCloudID
    }

    var body: some View {
        HStack(spacing: 12) {
            thumbnailView
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text(project.title)
                    .font(.headline)
                HStack {
                    Text("\(project.clips?.count ?? 0) clips")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(Self.dateFormatter.string(from: project.updatedAt))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 4)
        .task(id: firstClipCloudID) {
            await loadThumbnail()
        }
    }

    @ViewBuilder
    private var thumbnailView: some View {
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

    private func loadThumbnail() async {
        guard let cloudID = firstClipCloudID else { return }
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [cloudID], options: nil)
        guard let asset = assets.firstObject else { return }

        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat

        let image: UIImage? = await withCheckedContinuation { continuation in
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: 168, height: 168),
                contentMode: .aspectFill,
                options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }

        if let cgImage = image?.cgImage {
            thumbnail = Image(decorative: cgImage, scale: 1.0)
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: VlogProject.self, inMemory: true)
}
