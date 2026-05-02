# Madeleine 計画書 (v6)

## 1. 概要

選択した複数のLive Photoから、それぞれの動画部分(シャッター前後の3秒)を短く切り出して順番に連結し、1本のvlog動画として書き出すiOSアプリ。

旅行の写真を数十枚撮っていれば、Live Photoが混ざっていることが多い。それらを後から「動画素材」として再利用することで、動画を意識的に撮らなくても"その日のvlog"が作れる、というのが価値の核。

**対応プラットフォーム**: iPhone / iPad(iCloudプライベート同期で自分のデバイス間で共有)

---

## 2. 命名について

アプリ名: **Madeleine** 🍪

### 命名の経緯

Shakshi3104のアプリ群が「機能のキーワードを音や意味でお菓子名にかける」命名パターン(**Waffle** 🧇 = silicon **wafer** から / **Gaufre** 🧇 = 同じくwafer由来のお菓子 / **Shortcake** 🍰 = Screen**Shot** にかけて / **Mille** 🥞 = ミルフィーユの"層(layer)")を取っていることから、今回もそのラインに乗せる。

**Madeleine** の由来は、マルセル・プルースト『失われた時を求めて』(1913) に登場する有名な一節。主人公が紅茶に浸したマドレーヌを口にした瞬間、幼少期に叔母がくれた同じマドレーヌの記憶が鮮烈に蘇る。このエピソードから、ある感覚が引き金となって過去の記憶が不意に呼び起こされる現象を **「マドレーヌ・モーメント(Madeleine moment)」** あるいは **「プルースト効果」** と呼ぶようになった。

Live Photoが捉える"ほんの数秒の瞬間"をきっかけに、旅の記憶全体が動画として蘇る —— というこのアプリの本質が、そのままマドレーヌ・モーメントのメタファーになっている。

---

## 3. データ設計の原則(重要)

Madeleineは **「OSの既存ストアを尊重し、自分では最小限しか持たない」** 方針をとる。Shakshi3104の他アプリ(Calories=HealthKit参照 / Waffle=永続化なし)と一貫した思想。

### 3.1 データの所在

```
┌────────────────────────────────────────────────┐
│ SwiftData + CloudKit (プライベート同期)         │
│  自分のデバイス間で同期される                    │
│  ・VlogProject                                 │
│    - タイトル、作成日                           │
│    - クリップの並びと尺(編集レシピ)             │
│    - 各クリップの cloudIdentifier              │
│    - 書き出した動画の cloudIdentifier          │
└────────────────────────────────────────────────┘
                   ↓ 参照のみ
┌────────────────────────────────────────────────┐
│ 写真アプリ (iCloud写真で自動同期)               │
│  ・素材のLive Photo(実データ)                  │
│  ・完成した動画(実データ)                      │
└────────────────────────────────────────────────┘
```

**プロジェクトの編集レシピはSwiftData/CloudKitで同期、実データ(Live Photo/完成動画)は写真アプリのiCloud写真が同期する** —— という2段構成。アプリ側は二重持ちしない。

### 3.2 原則

- **素材のLive Photo** は複製せず、**`cloudIdentifier`(iCloud写真の永続ID)** を保存する
- **完成した動画** はカメラロールに保存し、同じく `cloudIdentifier` を保存する
- アプリのDocumentsに動画を複製しない
- `FileManager.temporaryDirectory` は、Live Photo抽出時のキャッシュとしてのみ使う

### 3.3 localIdentifier vs cloudIdentifier(最重要)

`PHAsset` には2つのIDがある:

| ID | 特徴 |
|---|---|
| `PHAsset.localIdentifier` | デバイスごとに異なる。iCloud写真が同期しても、iPhoneとiPadで別の値になる |
| `PHAsset.cloudIdentifier`(iOS 16+) | デバイス間で一意。iCloud写真上の永続ID |

**Madeleineでは必ず `cloudIdentifier` を保存する**。`localIdentifier` を保存するとiPadでプロジェクトを開いた時に素材が見つからない。

### 3.4 トレードオフと対処

| 問題 | 対処 |
|---|---|
| iCloud写真がオフの場合、素材がiPadにない | 「素材が見つかりません。iCloud写真を有効にしてください」と案内 |
| 素材のLive Photoが削除されると再編集不能 | Home画面でその旨表示。完成動画は残っているので再生は可能 |
| 完成動画が削除されると履歴から消える | Home画面で「動画が見つかりません」と表示、編集レシピは残しておいて再書き出し可能 |
| iCloud写真にあるが未ダウンロード | `PHAssetResourceRequestOptions.isNetworkAccessAllowed = true` + 進捗表示 |
| SwiftDataとCloudKit間の同期タイムラグ | アプリ起動時にしばらく待つ。初回起動時のローディングを明示 |

---

## 4. 技術スタック

| 項目 | 選定 |
|---|---|
| UI | **SwiftUI**(Liquid Glass対応) |
| 状態管理 | **`@Observable`** マクロ |
| 永続化 | **SwiftData** + **CloudKit**(プライベート同期) |
| 素材/完成品 | **写真アプリ**(参照のみ、`cloudIdentifier`で参照) |
| 最小iOS | **iOS 26.0** |
| Xcode | **26.0 以降** |
| Swift | **Swift 6.1+** |
| Bundle ID | `com.shakshi.Madeleine` |
| CloudKit Container | `iCloud.com.shakshi.Madeleine` |

### iOS 26を選んだ理由

- Shakshi3104の最新アプリ(Calories)と揃える
- **Liquid Glass** マテリアルをEditor/Home画面の演出に使える
- SwiftData がより安定(`@Model` の inheritance 等が iOS 26で追加)
- Swift 6.1+ の Concurrency Check が明確
- PhotosKit の `cloudIdentifier` 周りが成熟

---

## 5. UI設計方針 — Liquid Glass

iOS 26の **Liquid Glass** マテリアルを控えめに採用する。派手に使うのではなく、**動画コンテンツを主役にするために周辺UIをガラスで浮かせる** 方針。

### 5.1 自動で適用される部分(再コンパイルするだけ)

- `NavigationStack` の NavigationBar
- `TabView` のタブバー
- `Toolbar` の toolbar item
- `sheet` の背景(特に partial-height sheet)
- `Alert`、システムボタン

→ Madeleineはナビゲーションに標準コンポーネントを使うので、**特別な実装なしにOSが自動で新デザインを適用**してくれる。

### 5.2 積極的に `glassEffect()` を使う箇所

| 画面 | 使い所 |
|---|---|
| **EditorView** | プレビュー動画の上に浮かぶツールバー(再生/書き出しボタン等)に `GlassEffectContainer` + `.glassEffect()` |
| **PreviewView(モーダル)** | 再生コントロールバーをガラスで浮かせる |
| **HomeView** | FAB(新規作成ボタン)を`.glassEffect(.regular.interactive())` で |

### 5.3 使わない箇所(HIG準拠)

- プロジェクトカードのサムネイル背景(コンテンツそのものなのでガラス不要)
- メインコンテンツエリア全体(ガラスは常に"浮いている"要素だけ)
- ガラスのネスト(`.glassEffect()` の中にさらに `.glassEffect()` は禁じ手)

### 5.4 主要API(参考)

```swift
// 基本
Text("Hello").padding().glassEffect()

// コンテナで複数要素をまとめる(モーフィング可能に)
GlassEffectContainer {
    Button("Play") { ... }.glassEffect()
    Button("Export") { ... }.glassEffect()
}

// インタラクティブ(タップで沈む等)
Button("Create") { ... }
    .glassEffect(.regular.interactive())

// モーフィング遷移(Namespaceで結合)
@Namespace var ns
Button { ... }
    .glassEffect()
    .glassEffectID("create", in: ns)
```

---

## 6. 画面一覧と実装区分

| # | 画面 | 実装区分 | 備考 |
|---|---|---|---|
| 1 | **HomeView** | 🛠 自作SwiftUI | プロジェクトグリッド + Liquid Glass FAB |
| 2 | **PhotosPicker呼び出し** | 🍎 Apple標準 | `PhotosPicker(matching: .livePhotos)` |
| 3 | **ExtractingView** | 🛠 自作SwiftUI | Live Photoから動画を抽出する進捗 |
| 4 | **EditorView** | 🛠 自作SwiftUI | タイムライン + Liquid Glass ツールバー |
| 5 | **PreviewView** | 🔶 半分AVKit | `VideoPlayer` をラップ、Glass コントロール |
| 6 | **ExportProgressView** | 🛠 自作SwiftUI(モーダル) | iOS 26 partial-height sheetで自動ガラス |
| 7 | **共有シート** | 🍎 Apple標準 | `ShareLink` |

### 画面遷移

```
Home
  ├─ プロジェクトタップ → Editor(既存プロジェクト編集)
  ├─ プロジェクトタップ → Preview(完成動画のみ再生)
  └─ FAB → PhotosPicker(OS) → Extracting → Editor(新規)

Editor
  ├─ プレビューボタン → Preview(モーダル)
  ├─ + ボタン → PhotosPicker(OS) → Extracting → Editor(追加)
  └─ 書き出し → ExportProgress → Home
```

---

## 7. Claude Code運用ルール

### 7.1 役割分担

| 作業 | 担当 |
|---|---|
| `.xcodeproj` の作成・ターゲット追加・Capability設定・Info.plistキー追加 | **人間(Xcode GUI)** |
| 新規Swiftファイルの**作成**とXcodeプロジェクトへの**登録** | **人間(Xcode GUI で "New File" → 保存)** |
| Swiftファイルの**中身を書く・編集する** | **Claude Code** |
| アセット(画像・色)追加 | **人間** |
| ビルド実行 | どちらでも |

### 7.2 新規ファイル追加のワークフロー

1. Xcodeで「File > New > File」→ Swift File を作成(空でよい)
2. Claude Codeに「このファイルに〇〇を実装して」と指示

**Claude Codeが勝手に`Write`ツールで新規Swiftファイルを作ると、`.pbxproj`に登録されずビルドから漏れる**。`CLAUDE.md`で明示的に禁止する。

---

## 8. プロジェクト構成

### 8.1 Xcodeでの初期セットアップ(人間の作業)

1. Xcode 26 で「iOS App」テンプレート、`Madeleine` という名前で作成
   - Interface: **SwiftUI**
   - Language: **Swift**
   - **Storage: SwiftData** ✅
   - **Host in CloudKit** ✅ (Storage=SwiftData時のみ選択可)
   - Testing System: **None**
2. Deployment Target を **iOS 26.0** に設定
3. Capability を追加:
   - **iCloud** → **CloudKit** チェック(Host in CloudKitを選んでいれば自動で追加済み)
   - **Background Modes** → **Remote notifications** チェック(**手動追加必要**)
4. `Info.plist` に権限2つを追加:
   - `Privacy - Photo Library Additions Usage Description`
   - `Privacy - Photo Library Usage Description`
5. `git init` + `xcuserdata/` `build/` を `.gitignore`
6. プロジェクトルートに `CLAUDE.md` を置く
7. Xcodeが自動生成した `Item.swift` と `ContentView.swift` を削除

### 8.2 MadeleineApp.swift の修正

```swift
import SwiftUI
import SwiftData

@main
struct MadeleineApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            VlogProject.self,
            VlogClip.self,
        ])
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .private("iCloud.com.shakshi.Madeleine")
        )

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            HomeView()
        }
        .modelContainer(sharedModelContainer)
    }
}
```

### 8.3 フォルダ構成

```
Madeleine/
├── App/
│   └── MadeleineApp.swift              (エントリ、ModelContainer設定)
├── Models/
│   ├── VlogProject.swift               @Model (CloudKit対応)
│   └── VlogClip.swift                  @Model (CloudKit対応)
├── Features/
│   ├── Home/
│   │   └── HomeView.swift
│   ├── Extracting/
│   │   └── ExtractingView.swift        Live Photo抽出中の進捗
│   ├── Editor/
│   │   ├── EditorView.swift
│   │   ├── EditorViewModel.swift       @Observable
│   │   └── TimelineView.swift
│   ├── Preview/
│   │   └── PreviewView.swift           VideoPlayerラッパー
│   └── Export/
│       └── ExportProgressView.swift    モーダル
├── Services/
│   ├── CloudIdentifierResolver.swift   local ⇔ cloud ID 変換
│   ├── LivePhotoExtractor.swift        PHAsset → 動画URL
│   ├── VideoComposer.swift             [VlogClip] → AVComposition
│   ├── VideoExporter.swift             AVAssetExportSession
│   └── PhotoLibrarySaver.swift         保存 + cloudID取得
└── Resources/
    └── Assets.xcassets
```

---

## 9. データモデル(SwiftData + CloudKit)

### 9.1 VlogProject

```swift
import SwiftData
import Foundation

@Model
final class VlogProject {
    // CloudKit対応: すべて初期値ありか Optional
    var id: UUID = UUID()
    var title: String = ""
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    /// 書き出した完成動画の cloudIdentifier
    var exportedVideoCloudID: String?

    /// 編集レシピ。順序は clip.order の昇順
    @Relationship(deleteRule: .cascade, inverse: \VlogClip.project)
    var clips: [VlogClip]? = []

    init(title: String = "New Vlog") {
        self.id = UUID()
        self.title = title
        self.createdAt = .now
        self.updatedAt = .now
    }
}
```

### 9.2 VlogClip

```swift
@Model
final class VlogClip {
    var id: UUID = UUID()
    var order: Int = 0

    /// 素材の Live Photo の cloudIdentifier
    var sourceCloudID: String = ""

    /// 切り出す開始時刻(ソース動画内、秒)。nilなら中央から切り出し
    var trimStart: Double?

    /// 切り出す長さ(秒)
    var trimDuration: Double = 1.0

    /// 逆参照(CloudKit対応のため必須)
    var project: VlogProject?

    init(order: Int, sourceCloudID: String, trimDuration: Double = 1.0) {
        self.id = UUID()
        self.order = order
        self.sourceCloudID = sourceCloudID
        self.trimDuration = trimDuration
    }
}
```

### 9.3 CloudKit対応の必須ルール

1. **すべてのプロパティに初期値か Optional**
2. **`@Relationship` は両方向に定義**(inverseを両側に)
3. **`@Attribute(.unique)` は使わない**

---

## 10. 主要サービスの骨格

### 10.1 CloudIdentifierResolver

```swift
import Photos

actor CloudIdentifierResolver {
    enum ResolveError: Error {
        case notFound
        case permissionDenied
    }

    /// localIdentifier → cloudIdentifier(保存時)
    func cloudID(fromLocal localID: String) async throws -> String {
        let mappings = PHPhotoLibrary.shared()
            .cloudIdentifierMappings(forLocalIdentifiers: [localID])
        guard let result = mappings[localID] else {
            throw ResolveError.notFound
        }
        return try result.get().stringValue
    }

    /// cloudIdentifier → PHAsset(読み込み時)
    func asset(fromCloud cloudID: String) async throws -> PHAsset {
        let pcid = PHCloudIdentifier(stringValue: cloudID)
        let mappings = PHPhotoLibrary.shared()
            .localIdentifierMappings(forCloudIdentifiers: [pcid])
        guard let result = mappings[pcid] else {
            throw ResolveError.notFound
        }
        let localID = try result.get()
        guard let asset = PHAsset.fetchAssets(
            withLocalIdentifiers: [localID], options: nil
        ).firstObject else {
            throw ResolveError.notFound
        }
        return asset
    }
}
```

### 10.2 LivePhotoExtractor

```swift
import Photos

actor LivePhotoExtractor {
    enum ExtractError: Error {
        case assetNotFound
        case notLivePhoto
        case noPairedVideo
        case writeFailed(Error)
    }

    private let resolver = CloudIdentifierResolver()

    func extractVideo(fromCloudID cloudID: String) async throws -> URL {
        let asset = try await resolver.asset(fromCloud: cloudID)
        guard asset.mediaSubtypes.contains(.photoLive) else {
            throw ExtractError.notLivePhoto
        }

        let livePhoto = try await requestLivePhoto(for: asset)

        let resources = PHAssetResource.assetResources(for: livePhoto)
        guard let videoResource = resources.first(where: { $0.type == .pairedVideo })
        else { throw ExtractError.noPairedVideo }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")

        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true

        return try await withCheckedThrowingContinuation { continuation in
            PHAssetResourceManager.default().writeData(
                for: videoResource, toFile: outputURL, options: options
            ) { error in
                if let error {
                    continuation.resume(throwing: ExtractError.writeFailed(error))
                } else {
                    continuation.resume(returning: outputURL)
                }
            }
        }
    }

    private func requestLivePhoto(for asset: PHAsset) async throws -> PHLivePhoto {
        try await withCheckedThrowingContinuation { continuation in
            let options = PHLivePhotoRequestOptions()
            options.isNetworkAccessAllowed = true
            options.deliveryMode = .highQualityFormat

            PHImageManager.default().requestLivePhoto(
                for: asset,
                targetSize: PHImageManagerMaximumSize,
                contentMode: .aspectFit,
                options: options
            ) { livePhoto, info in
                if let livePhoto {
                    continuation.resume(returning: livePhoto)
                } else if let error = info?[PHImageErrorKey] as? Error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(throwing: ExtractError.noPairedVideo)
                }
            }
        }
    }
}
```

### 10.3 VideoComposer

```swift
import AVFoundation

struct VideoComposer {
    enum ComposerError: Error { case trackCreationFailed }

    func compose(
        clips: [VlogClip],
        videoURLs: [UUID: URL],
        renderSize: CGSize = CGSize(width: 1080, height: 1920)
    ) async throws -> (AVComposition, AVMutableVideoComposition) {
        let composition = AVMutableComposition()
        guard let videoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else { throw ComposerError.trackCreationFailed }

        var instructions: [AVMutableVideoCompositionInstruction] = []
        var cursor = CMTime.zero
        let sortedClips = clips.sorted { $0.order < $1.order }

        for clip in sortedClips {
            guard let url = videoURLs[clip.id] else { continue }
            let asset = AVURLAsset(url: url)
            let srcVideoTracks = try await asset.loadTracks(withMediaType: .video)
            guard let srcVideo = srcVideoTracks.first else { continue }

            let duration = try await asset.load(.duration)
            let clipLen = CMTime(seconds: clip.trimDuration, preferredTimescale: 600)

            let startTime: CMTime
            if let ts = clip.trimStart {
                startTime = CMTime(seconds: ts, preferredTimescale: 600)
            } else {
                let center = CMTimeMultiplyByFloat64(duration, multiplier: 0.5)
                startTime = CMTimeSubtract(
                    center,
                    CMTimeMultiplyByFloat64(clipLen, multiplier: 0.5)
                )
            }
            let range = CMTimeRange(start: startTime, duration: clipLen)

            try videoTrack.insertTimeRange(range, of: srcVideo, at: cursor)

            let layerInstruction = AVMutableVideoCompositionLayerInstruction(
                assetTrack: videoTrack
            )
            let transform = try await computeTransform(
                for: srcVideo, renderSize: renderSize
            )
            layerInstruction.setTransform(transform, at: cursor)

            let instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = CMTimeRange(start: cursor, duration: clipLen)
            instruction.layerInstructions = [layerInstruction]
            instructions.append(instruction)

            cursor = CMTimeAdd(cursor, clipLen)
        }

        let videoComp = AVMutableVideoComposition()
        videoComp.renderSize = renderSize
        videoComp.frameDuration = CMTime(value: 1, timescale: 30)
        videoComp.instructions = instructions
        return (composition, videoComp)
    }

    private func computeTransform(
        for track: AVAssetTrack,
        renderSize: CGSize
    ) async throws -> CGAffineTransform {
        let naturalSize = try await track.load(.naturalSize)
        let preferred = try await track.load(.preferredTransform)
        let transformed = CGRect(origin: .zero, size: naturalSize).applying(preferred)
        let displaySize = CGSize(
            width: abs(transformed.width),
            height: abs(transformed.height)
        )
        let scale = max(
            renderSize.width / displaySize.width,
            renderSize.height / displaySize.height
        )
        let scaledSize = CGSize(
            width: displaySize.width * scale,
            height: displaySize.height * scale
        )
        let tx = (renderSize.width - scaledSize.width) / 2
        let ty = (renderSize.height - scaledSize.height) / 2
        return preferred
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(translationX: tx, y: ty))
    }
}
```

### 10.4 PhotoLibrarySaver

```swift
import Photos

struct PhotoLibrarySaver {
    enum SaveError: Error {
        case permissionDenied
        case saveFailed(Error)
        case noIdentifier
        case noCloudID
    }

    private let resolver = CloudIdentifierResolver()

    func save(videoAt url: URL) async throws -> String {
        var savedLocalID: String?

        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .video, fileURL: url, options: nil)
            savedLocalID = request.placeholderForCreatedAsset?.localIdentifier
        }

        guard let localID = savedLocalID else {
            throw SaveError.noIdentifier
        }

        // 保存直後は cloudID がまだ取れないのでリトライ
        for attempt in 0..<10 {
            do {
                return try await resolver.cloudID(fromLocal: localID)
            } catch {
                if attempt < 9 {
                    try await Task.sleep(for: .seconds(1))
                }
            }
        }
        throw SaveError.noCloudID
    }
}
```

### 10.5 PhotosPicker 呼び出し

```swift
import SwiftUI
import PhotosUI

struct NewProjectPickerButton: View {
    @State private var selections: [PhotosPickerItem] = []
    let onSelected: ([String]) -> Void
    private let resolver = CloudIdentifierResolver()

    var body: some View {
        PhotosPicker(
            selection: $selections,
            maxSelectionCount: 30,
            matching: .livePhotos
        ) {
            Label("Live Photoを選ぶ", systemImage: "plus")
        }
        .onChange(of: selections) { _, newItems in
            Task { await handleSelection(newItems) }
        }
    }

    private func handleSelection(_ items: [PhotosPickerItem]) async {
        var cloudIDs: [String] = []
        for item in items {
            guard let localID = item.itemIdentifier else { continue }
            do {
                let cloudID = try await resolver.cloudID(fromLocal: localID)
                cloudIDs.append(cloudID)
            } catch {
                print("Failed to resolve cloudID for \(localID): \(error)")
            }
        }
        await MainActor.run { onSelected(cloudIDs) }
    }
}
```

---

## 11. 段階的な実装ロードマップ

### Step 1: プロジェクト骨格(人間主体)
- [ ] Xcode 26でプロジェクト作成(Storage: SwiftData + Host in CloudKit)
- [ ] Capability: Background Modes(Remote notifications)を追加
- [ ] Info.plistに権限2つ追加
- [ ] Deployment Target を iOS 26.0 に
- [ ] フォルダ構成で空ファイル作成
- [ ] `Item.swift` と `ContentView.swift` 削除
- [ ] git 初期化、CLAUDE.md 配置

### Step 2: データモデル(Claude Code)
- [ ] `VlogProject.swift`、`VlogClip.swift`
- [ ] `MadeleineApp.swift` のModelContainer設定

### Step 3: ID変換サービス(Claude Code)
- [ ] `CloudIdentifierResolver.swift`

### Step 4: Live Photo抽出(Claude Code)
- [ ] `LivePhotoExtractor.swift`

### Step 5: PhotosPicker統合(Claude Code + 動作確認)
- [ ] `NewProjectPickerButton`

### Step 6: 抽出フロー(Claude Code)
- [ ] `ExtractingView.swift`

### Step 7: 動画連結(Claude Code)
- [ ] `VideoComposer.swift`

### Step 8: エクスポータ(Claude Code)
- [ ] `VideoExporter.swift`

### Step 9: カメラロール保存(Claude Code)
- [ ] `PhotoLibrarySaver.swift`

### Step 10: エディタUI(Claude Code)
- [ ] `EditorView.swift` + `EditorViewModel.swift`
- [ ] タイムラインツールバーに `GlassEffectContainer` 適用

### Step 11: プレビュー(Claude Code)
- [ ] `PreviewView.swift`(`VideoPlayer`ラップ、Glassコントロール)

### Step 12: ホーム(Claude Code)
- [ ] `HomeView.swift`(`@Query`、プロジェクトグリッド、Glass FAB)

### Step 13: 書き出し進捗(Claude Code)
- [ ] `ExportProgressView.swift`(partial-height sheetで自動Glass)

### Step 14: エラーハンドリング(Claude Code)
- [ ] 素材消失、ダウンロード待ち、同期タイムラグ

### Step 15: 仕上げ
- [ ] アプリアイコン、空状態のイラスト
- [ ] iPhone + iPad実機でiCloud同期動作確認

---

## 12. MVPと段階的拡張

### MVP
- [x] PhotosPickerでLive Photoを複数選択
- [x] 各クリップから中央1秒を切り出して連結
- [x] 縦動画1080x1920で書き出し
- [x] カメラロールに保存、cloudIDをSwiftDataに
- [x] 過去プロジェクト一覧(Home)
- [x] iPhoneとiPadでSwiftData+CloudKit同期

### v1.1
- [ ] クリップごとの尺調整(0.5〜3.0秒)
- [ ] クリップ並び替え(ドラッグ)・削除
- [ ] プレビュー再生

### v1.2
- [ ] BGM追加
- [ ] トランジション(クロスフェード)
- [ ] 出力向き切替(縦/横/正方形)

### v2.0
- [ ] 切り出し位置を前/中/後から選択可能に
- [ ] テキストオーバーレイ
- [ ] 通常写真(Ken Burns)混在可能に
- [ ] フィルター(Core Image)

---

## 13. 落とし穴チェックリスト

### プロジェクト運用
1. **新規ファイル追加はXcodeから** — Claude Codeが勝手にSwiftファイルを作るとビルドに含まれない
2. **URLを永続化しない** — 一時ディレクトリのURLは再起動で無効

### データ設計(iCloud関連)
3. **`localIdentifier`ではなく`cloudIdentifier`を保存**
4. **保存直後のcloudID取得にはリトライ必須** — iCloudアップロードに時間がかかる
5. **SwiftData同期のタイムラグ** — アプリ起動直後はまだ同期されていない

### CloudKit × SwiftData の制約
6. **`@Attribute(.unique)` は使わない**
7. **`@Relationship` は双方向に** — `inverse:` 指定が必要
8. **すべてのプロパティに初期値かOptional**

### Photos関連
9. **iCloud写真オフの場合の案内**
10. **素材消失ハンドリング** — `cloudIdentifierMappings`が空辞書を返すケース
11. **iCloudダウンロード待ち** — `isNetworkAccessAllowed = true` + 進捗表示
12. **`itemIdentifier`がnil** — スキップ実装

### メディア関連
13. **向きの不揃い** — `preferredTransform`を必ず適用
14. **音声のブツ切り** — MVPでは音声ミュート
15. **シャッター前後のブレ** — 中央1秒切り出しが無難
16. **実機必須** — Live Photoはシミュレータで撮影できない

### Liquid Glass(iOS 26)
17. **`.glassEffect()` のネスト禁止** — 中に`.glassEffect()`を入れると視覚的に破綻
18. **コンテンツそのものにガラスをかけない** — ガラスは"浮いている"UI要素のためのもの
19. **`.prominent` は存在しない** — Glass variantは `.regular`、`.clear`、`.identity` のみ

---

## 14. 参考リンク

- Apple Docs
  - [PHCloudIdentifier](https://developer.apple.com/documentation/photokit/phcloudidentifier)
  - [cloudIdentifierMappings(forLocalIdentifiers:)](https://developer.apple.com/documentation/photokit/phphotolibrary/cloudidentifiermappings(forlocalidentifiers:))
  - [Applying Liquid Glass to custom views](https://developer.apple.com/documentation/SwiftUI/Applying-Liquid-Glass-to-custom-views)
  - [Build a SwiftUI app with the new design (WWDC25)](https://developer.apple.com/videos/play/wwdc2025/323/)
- [LimitPoint/LivePhoto](https://github.com/LimitPoint/LivePhoto) — Live Photo抽出の参考実装
- [conorluddy/LiquidGlassReference](https://github.com/conorluddy/LiquidGlassReference) — Liquid Glass API網羅
- Madeleine moment: Wikipedia [Involuntary memory](https://en.wikipedia.org/wiki/Involuntary_memory), [In Search of Lost Time](https://en.wikipedia.org/wiki/In_Search_of_Lost_Time)
