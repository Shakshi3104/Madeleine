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
    case autoSelectSetup
    case autoSelecting(from: Date, to: Date, targetCount: Int)

    static func == (lhs: AppDestination, rhs: AppDestination) -> Bool {
        switch (lhs, rhs) {
        case let (.extracting(a), .extracting(b)):
            return a.persistentModelID == b.persistentModelID
        case let (.editor(a, _), .editor(b, _)):
            return a.persistentModelID == b.persistentModelID
        case (.autoSelectSetup, .autoSelectSetup):
            return true
        case let (.autoSelecting(a1, a2, a3), .autoSelecting(b1, b2, b3)):
            return a1 == b1 && a2 == b2 && a3 == b3
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
        case .autoSelectSetup:
            hasher.combine(2)
        case let .autoSelecting(from, to, target):
            hasher.combine(3)
            hasher.combine(from)
            hasher.combine(to)
            hasher.combine(target)
        }
    }
}

// MARK: - ContentView

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \VlogProject.createdAt, order: .reverse) private var projects: [VlogProject]

    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var navigationPath = NavigationPath()
    @State private var showAbout = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var showAlert = false
    @State private var isShowingPhotosPicker = false
    @State private var autoSelectErrorMessage: String?

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
                        Image(systemName: "ellipsis.circle")
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
                case .autoSelectSetup:
                    AutoSelectSetupView { from, to, target in
                        navigationPath.append(AppDestination.autoSelecting(from: from, to: to, targetCount: target))
                    }
                case let .autoSelecting(from, to, target):
                    AutoSelectingView(
                        fromDate: from,
                        toDate: to,
                        targetCount: target,
                        onCompleted: { clips in
                            handleAutoSelectCompleted(clips: clips, from: from, to: to, targetCount: target)
                        },
                        onCancelled: {
                            navigationPath = NavigationPath()
                        },
                        onFailed: { error in
                            navigationPath = NavigationPath()
                            autoSelectErrorMessage = autoSelectMessage(for: error)
                        }
                    )
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
        .task {
            if PHPhotoLibrary.authorizationStatus(for: .readWrite) == .notDetermined {
                await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            }
        }
        .alert(
            "Auto Select Failed",
            isPresented: Binding(
                get: { autoSelectErrorMessage != nil },
                set: { if !$0 { autoSelectErrorMessage = nil } }
            ),
            presenting: autoSelectErrorMessage
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { message in
            Text(message)
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
                    let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
                    if status == .denied || status == .restricted {
                        alertTitle = "Photos Access Required"
                        alertMessage = "Please allow Madeleine to access your Photos in Settings."
                        showAlert = true
                    } else if (project.clips ?? []).isEmpty {
                        navigationPath.append(AppDestination.editor(project, [:]))
                    } else {
                        navigationPath.append(AppDestination.extracting(project))
                    }
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
            Menu {
                Button {
                    navigationPath.append(AppDestination.autoSelectSetup)
                } label: {
                    Label("Pick photos from a trip", systemImage: "sparkles")
                }
                Button {
                    isShowingPhotosPicker = true
                } label: {
                    Label("Pick photos manually", systemImage: "plus")
                }
            } label: {
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
        .photosPicker(
            isPresented: $isShowingPhotosPicker,
            selection: $selectedPhotos,
            maxSelectionCount: 30,
            matching: .livePhotos,
            photoLibrary: .shared()
        )
        .onChange(of: selectedPhotos) { _, newItems in
            guard !newItems.isEmpty else { return }
            let project = createProject(from: newItems)
            selectedPhotos = []
            guard !(project.clips ?? []).isEmpty else {
                modelContext.delete(project)
                let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
                if status == .denied || status == .restricted {
                    alertTitle = "Photos Access Required"
                    alertMessage = "Please allow Madeleine to access your Photos in Settings."
                } else {
                    alertTitle = "Couldn't Create Vlog"
                    alertMessage = "No Live Photos were selected. Please select Live Photos to create a vlog."
                }
                showAlert = true
                return
            }
            navigationPath.append(AppDestination.extracting(project))
        }
        .alert(alertTitle, isPresented: $showAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage)
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
            guard let asset = assets.firstObject else { continue }
            let filename = PHAssetResource.assetResources(for: asset).first?.originalFilename ?? ""
            let captureDate = asset.creationDate
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

    // MARK: - Auto Select Helpers

    private func handleAutoSelectCompleted(
        clips curatedClips: [AutoCurator.CuratedClip],
        from: Date,
        to: Date,
        targetCount: Int
    ) {
        let project = createAutoSelectedProject(
            curatedClips: curatedClips,
            from: from,
            to: to,
            targetCount: targetCount
        )
        var newPath = NavigationPath()
        newPath.append(AppDestination.extracting(project))
        navigationPath = newPath
    }

    private func createAutoSelectedProject(
        curatedClips: [AutoCurator.CuratedClip],
        from: Date,
        to: Date,
        targetCount: Int
    ) -> VlogProject {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy/MM/dd"
        let defaultTitle = "Vlog \(dateFormatter.string(from: Date()))"
        let project = VlogProject(title: defaultTitle)
        project.isAutoSelected = true
        project.autoSelectFromDate = from
        project.autoSelectToDate = to
        project.autoSelectTargetCount = targetCount
        modelContext.insert(project)

        for curated in curatedClips {
            let assets = PHAsset.fetchAssets(withLocalIdentifiers: [curated.sourceCloudID], options: nil)
            let filename: String
            let captureDate: Date?
            if let asset = assets.firstObject {
                filename = PHAssetResource.assetResources(for: asset).first?.originalFilename ?? ""
                captureDate = asset.creationDate
            } else {
                filename = ""
                captureDate = nil
            }
            let clip = VlogClip(
                order: curated.order,
                sourceCloudID: curated.sourceCloudID,
                originalFilename: filename,
                captureDate: captureDate
            )
            clip.project = project
            modelContext.insert(clip)
        }

        project.updatedAt = .now
        return project
    }

    private func autoSelectMessage(for error: Error) -> String {
        if let curationError = error as? AutoCurator.CurationError {
            switch curationError {
            case .noAssetsFound:
                return "No Live Photos found in this date range. Try widening the range and tap again."
            case .evaluationFailed:
                return "Couldn't read any of the photos in this range. They may only be stored in iCloud — open the Photos app and let them download, then try again."
            case .noResults:
                return "All photos in this range were skipped as utility (screenshots, receipts, etc.). Try a different date range."
            }
        }
        return error.localizedDescription
    }
}

// MARK: - Project Row

struct VlogProjectRow: View {
    let project: VlogProject
    @State private var thumbnail: Image?
    @Environment(\.scenePhase) private var scenePhase

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
                    Text(Self.dateFormatter.string(from: project.createdAt))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 4)
        .task(id: firstClipCloudID) {
            await loadThumbnail()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task { await loadThumbnail() }
            }
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
        guard let cloudID = firstClipCloudID else {
            thumbnail = nil
            return
        }
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [cloudID], options: nil)
        guard let asset = assets.firstObject else {
            thumbnail = nil
            return
        }

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
