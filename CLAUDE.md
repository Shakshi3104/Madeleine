# Madeleine — Project Rules for Claude Code

This document tells Claude Code how to work inside this repo. Read it before making changes.

---

## 1. Overview

**Madeleine** 🍪 is an iOS app that stitches user-selected Live Photos into a short travel vlog video.

The name comes from the "Madeleine moment" in Proust's *In Search of Lost Time* — a sensory cue (tasting a tea-soaked madeleine) that unexpectedly revives a flood of childhood memories. Live Photos function the same way for travel: one tiny clip from a still photo can pull back the whole day.

This project follows the naming convention of Shakshi3104's other apps: a dessert name tied to the feature (Waffle 🧇 = wafer, Shortcake 🍰 = screenshot, Mille 🥞 = layer, etc).

---

## 2. Tech Stack

| Item | Choice |
|---|---|
| UI | SwiftUI with Liquid Glass |
| State | `@Observable` macro (NOT `ObservableObject`) |
| Persistence | SwiftData with CloudKit private sync |
| Media refs | `PHAsset.cloudIdentifier` (see §3) |
| Minimum iOS | **26.0** |
| Bundle ID | `com.shakshi.Madeleine` |
| CloudKit Container | `iCloud.com.shakshi.Madeleine` |
| Xcode | 26.0+ |
| Swift | 6.1+ |

---

## 3. Data Strategy (CRITICAL)

We do **not** duplicate photo or video data inside the app.

- **Source Live Photos** live in the user's Photos library. They sync across devices via iCloud Photos.
- **Exported videos** are saved to Camera Roll. They also sync via iCloud Photos.
- **SwiftData + CloudKit** holds only the *editing recipe*: project metadata, clip order, trim duration, and `cloudIdentifier` strings that point into the Photos library.

### Always use `cloudIdentifier`, never `localIdentifier` for persistence

`PHAsset.localIdentifier` differs between devices. An asset on iPhone and the "same" asset on iPad have different local IDs. `cloudIdentifier` (iOS 16+) is stable across devices for the same iCloud Photos library.

Use `Services/CloudIdentifierResolver.swift` for all conversions:
- Save: `localIdentifier` → `cloudIdentifier` before writing to SwiftData
- Load: `cloudIdentifier` → `PHAsset` before any Photos/AVFoundation work

### Temporary files

`FileManager.default.temporaryDirectory` is a cache for extracted Live Photo paired videos. These URLs are **never** persisted to SwiftData. They can be invalidated between launches.

---

## 4. Build & Test Commands

Prefer these over opening Xcode. Use them to verify your changes compile.

### Build for simulator

```bash
xcodebuild -scheme Madeleine \
  -destination 'platform=iOS Simulator,name=iPhone 15 Pro' \
  -configuration Debug \
  build
```

### Clean build

```bash
xcodebuild -scheme Madeleine clean
```

### List available simulators

```bash
xcrun simctl list devices available
```

If a build fails, read the output carefully and fix the errors before reporting back. Do not stop at the first error — fix as many as you can in one pass.

---

## 5. Code Style

- **SwiftUI + `@Observable`**. Never use `ObservableObject` / `@Published`.
- **iOS 26+ only**. Use new APIs freely: `#Preview`, `.glassEffect()`, `GlassEffectContainer`, `PhotosPicker(matching: .livePhotos)`, latest `AVAsset` async loaders.
- **async/await everywhere**. Do not add new completion-handler APIs. If wrapping one, use `withCheckedThrowingContinuation`.
- **`throws` for errors**, not `Result`. Define a nested `enum ...Error: Error` on the type that throws.
- **Typed throws** (`throws(MyError)`) may be used where beneficial (Swift 6.1+).
- **One screen per file**. View and its `@Observable` ViewModel can share a file.
- **No force-unwrap** in production code paths. `guard let ... else { throw ... }` is fine.
- **Prefer `struct` and `actor` over `class`.** Use `class` only for `@Model`.

### Naming

- Views end with `View` (e.g. `HomeView`)
- ViewModels end with `ViewModel`
- Services are nouns (`LivePhotoExtractor`, `VideoComposer`)

---

## 6. UI Guidelines — Liquid Glass

### 6.1 Where it applies automatically

Standard SwiftUI containers pick up Liquid Glass just by recompiling against Xcode 26:

- `NavigationStack` / navigation bars
- `TabView` / tab bars
- `Toolbar` items
- `sheet` backgrounds (especially partial-height sheets)
- `Alert`, `.confirmationDialog`, system buttons

**Do not** override `.presentationBackground` on sheets — let the new material shine.

### 6.2 Where to explicitly opt in

Use `.glassEffect()` only for floating controls over content:

- **EditorView**: tool buttons floating over the preview
- **PreviewView**: playback controls
- **HomeView**: the "New Vlog" FAB

Pattern for grouped morphable buttons:

```swift
@Namespace private var glassNS

GlassEffectContainer {
    HStack(spacing: 12) {
        Button { ... } label: { Image(systemName: "play.fill") }
            .glassEffect()
            .glassEffectID("play", in: glassNS)
        Button { ... } label: { Image(systemName: "square.and.arrow.up") }
            .glassEffect()
            .glassEffectID("export", in: glassNS)
    }
}
```

For a single interactive button:

```swift
Button { ... } label: { Image(systemName: "plus") }
    .glassEffect(.regular.interactive())
```

### 6.3 Rules

- **No nesting.** A `.glassEffect()` inside another `.glassEffect()` breaks visually.
- **No glass on content itself.** Glass is for floating chrome, not for photos/video.
- **Valid variants**: `.regular`, `.clear`, `.identity`. `.prominent` does NOT exist — do not hallucinate it.
- **Don't override sheet backgrounds.** `.presentationBackground(.clear)` etc. disables the new material.

---

## 7. SwiftData + CloudKit Rules

CloudKit backing imposes three constraints on `@Model` types. All three are mandatory.

### 7.1 Every property must have a default value or be Optional

```swift
// GOOD
var id: UUID = UUID()
var title: String = ""
var exportedVideoCloudID: String?

// BAD — CloudKit will refuse to initialize the container
var id: UUID
var title: String
```

### 7.2 `@Relationship` must be defined on both sides with `inverse:`

```swift
// In VlogProject
@Relationship(deleteRule: .cascade, inverse: \VlogClip.project)
var clips: [VlogClip]? = []

// In VlogClip
var project: VlogProject?
```

### 7.3 Do NOT use `@Attribute(.unique)`

CloudKit does not enforce uniqueness. Uniqueness must be handled at the application level if ever needed.

---

## 8. File Creation Rules (IMPORTANT)

**Never create new `.swift` files yourself.** The Xcode project is managed by hand, and new files must be registered into `.pbxproj` through Xcode's GUI. Files you create with `Write` or `touch` will not be included in the build.

If the user's request requires a new file:

1. **Stop.**
2. Tell the user: "I need a new file at `<path>`. Please create an empty Swift file there in Xcode, then I'll implement it."
3. Wait for the user to confirm the file exists.
4. Then write its contents.

You may freely edit, rename, or delete content *within* existing files.

---

## 9. Concurrency

Swift 6.1 / iOS 26 concurrency checking is strict. Follow these rules to avoid data races.

- **Heavy work goes in `actor` or `Task.detached`.** AVFoundation composition, Photos resource extraction, file I/O — never on the main actor.
- **UI updates must be `@MainActor`**. SwiftUI views are `@MainActor` by default; when calling into them from an `actor`, hop explicitly: `await MainActor.run { ... }`.
- **Services are `actor` when they own state** (e.g. `LivePhotoExtractor`, `CloudIdentifierResolver`), `struct` when stateless (e.g. `VideoComposer`).
- **`@Observable` classes are main-actor-isolated** by default. Access them only from the main actor.

---

## 10. Project Structure

```
Madeleine/
├── App/
│   └── MadeleineApp.swift              (entry point, ModelContainer setup)
├── Models/
│   ├── VlogProject.swift               @Model
│   └── VlogClip.swift                  @Model
├── Features/
│   ├── Home/
│   │   └── HomeView.swift
│   ├── Extracting/
│   │   └── ExtractingView.swift        progress while extracting Live Photos
│   ├── Editor/
│   │   ├── EditorView.swift
│   │   ├── EditorViewModel.swift       @Observable
│   │   └── TimelineView.swift
│   ├── Preview/
│   │   └── PreviewView.swift           wraps AVKit's VideoPlayer
│   └── Export/
│       └── ExportProgressView.swift    modal with progress bar
├── Services/
│   ├── CloudIdentifierResolver.swift   local ⇔ cloud ID conversion
│   ├── LivePhotoExtractor.swift        PHAsset → paired video URL
│   ├── VideoComposer.swift             [VlogClip] → AVComposition
│   ├── VideoExporter.swift             AVAssetExportSession wrapper
│   └── PhotoLibrarySaver.swift         save to Camera Roll, return cloudID
└── Resources/
    └── Assets.xcassets
```

---

## 11. Implementation Status

Keep this checklist updated as work progresses. Check off items when they compile, build, and have been manually smoke-tested.

### Phase 1 — Foundation
- [ ] Xcode project created with SwiftData + Host in CloudKit
- [ ] Background Modes (Remote notifications) capability added
- [ ] Info.plist: `NSPhotoLibraryAddUsageDescription`, `NSPhotoLibraryUsageDescription`
- [ ] Deployment Target set to iOS 26.0
- [ ] `MadeleineApp.swift` configured with `cloudKitDatabase: .private(...)`
- [ ] Template `Item.swift` and `ContentView.swift` deleted

### Phase 2 — Models
- [ ] `Models/VlogProject.swift`
- [ ] `Models/VlogClip.swift`

### Phase 3 — Services
- [ ] `Services/CloudIdentifierResolver.swift`
- [ ] `Services/LivePhotoExtractor.swift`
- [ ] `Services/VideoComposer.swift`
- [ ] `Services/VideoExporter.swift`
- [ ] `Services/PhotoLibrarySaver.swift`

### Phase 4 — Screens
- [ ] `HomeView` (with `@Query`, Glass FAB)
- [ ] PhotosPicker integration
- [ ] `ExtractingView`
- [ ] `EditorView` + `EditorViewModel` (Glass toolbar)
- [ ] `TimelineView`
- [ ] `PreviewView` (Glass playback controls)
- [ ] `ExportProgressView`

### Phase 5 — Polish
- [ ] Empty states (no projects, no Live Photos available)
- [ ] Source-missing handling (asset deleted from Photos)
- [ ] iCloud download progress when extracting
- [ ] App icon, launch screen
- [ ] Real-device testing on iPhone and iPad for iCloud sync

---

## 12. Common Pitfalls

### Workflow
1. **New file → stop and ask the user first** (§8). Do not run `touch` or `Write` for new `.swift` files.
2. **Temporary URLs are never persisted.** If you need a reference that survives app launches, use a `cloudIdentifier`.

### CloudKit × SwiftData
3. Every `@Model` property needs a default or must be Optional (§7.1).
4. `@Relationship` must be defined on both sides (§7.2).
5. Do not use `@Attribute(.unique)` (§7.3).

### Photos
6. **Always use `cloudIdentifier` for persistence**, not `localIdentifier`.
7. **`cloudIdentifier` is not immediately available after save.** When saving a newly exported video, retry the `cloudIdentifierMappings` call for up to ~10 seconds before giving up.
8. **`PhotosPickerItem.itemIdentifier` can be nil.** Skip items that have no identifier rather than crashing.
9. **Set `isNetworkAccessAllowed = true`** on `PHAssetResourceRequestOptions` and `PHLivePhotoRequestOptions` — users may have source photos in iCloud but not on-device.

### Media
10. **Apply `preferredTransform`** via `AVMutableVideoCompositionLayerInstruction`. Without it, portrait clips will render sideways.
11. **Mute audio for MVP.** Stitched one-second clips have audible cuts. Audio / BGM comes in v1.2.
12. **Trim from the center of each Live Photo.** The first ~0.5 s is usually motion blur from raising the phone.

### Liquid Glass
13. **Do not nest `.glassEffect()`**. Use `GlassEffectContainer` to group, not nesting.
14. **Do not apply glass to content itself** (photos, video frames, long text blocks).
15. **`.prominent` is not a valid variant.** Only `.regular`, `.clear`, `.identity` exist. Do not hallucinate APIs.
16. **Do not override sheet backgrounds.** Remove `.presentationBackground(.clear)` etc. to let iOS 26 auto-apply glass.

### Testing
17. **Simulator cannot capture Live Photos.** To test, drag existing Live Photo bundles into Photos.app of the simulator, or test on a real device.

---

## 13. How to Work With the User

- When the user describes a feature, first confirm the scope, then implement one layer at a time (model → service → view).
- After each file change, run the build command (§4) before declaring success.
- If a build fails, fix errors yourself — do not ask the user to fix Swift compile errors unless you genuinely cannot.
- If a task requires a new file, UI asset, or capability change, stop and tell the user what to do in Xcode.
- Update §11 Implementation Status as you complete items.
