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
    @State private var photoAuthStatus: PHAuthorizationStatus = .notDetermined

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
            .navigationTitle("Madeleine")
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
        .task {
            photoAuthStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
            if photoAuthStatus == .notDetermined {
                photoAuthStatus = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            }
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
        let project = VlogProject(title: "New Vlog")
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

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(project.title)
                .font(.headline)
            HStack {
                Text("\(project.clips?.count ?? 0) clips")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(project.updatedAt, style: .date)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: VlogProject.self, inMemory: true)
}
