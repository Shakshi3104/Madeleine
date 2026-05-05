# Madeleine — Project Rules for Claude Code

This document tells Claude Code how to work inside this repo. Read it before making changes.

---

## 1. Overview

**Madeleine** 🥧 is an iOS app that stitches user-selected Live Photos into a short travel vlog video.

The name comes from the "Madeleine moment" in Proust's *In Search of Lost Time* — a sensory cue (tasting a tea-soaked madeleine) that unexpectedly revives a flood of childhood memories. Live Photos function the same way for travel: one tiny clip from a still photo can pull back the whole day.

This project follows the naming convention of Shakshi3104's other apps: a dessert name tied to the feature (Waffle 🧇 = wafer, Shortcake 🍰 = screenshot, Mille 🥞 = layer, etc).

---

## 2. Tech Stack

| Item | Choice |
|---|---|
| UI | SwiftUI with Liquid Glass |
| State | `@Observable` macro (NOT `ObservableObject`) |
| Persistence | SwiftData (single-device, no CloudKit sync) |
| Media refs | `PHAsset.localIdentifier` |
| Minimum iOS | **26.0** |
| Bundle ID | `com.shakshi.Madeleine` |
| Xcode | 26.0+ |
| Swift | 6.1+ |
| Accent Color | Golden Orange `#F5A623` |

---

## 3. Data Strategy (CRITICAL)

We do **not** duplicate photo or video data inside the app.

- **Source Live Photos** live in the user's Photos library.
- **Exported videos** are shared via the system share sheet (not saved to Camera Roll automatically).
- **SwiftData** holds only the *editing recipe*: project metadata, clip order, trim duration, and `PHAsset.localIdentifier` references that point into the Photos library.
- **Single-device only.** CloudKit sync is intentionally not enabled — projects do not sync across devices. The `@Model` types still follow CloudKit constraints (§7) so this can be revisited later, and `Service/CloudIdentifierResolver.swift` exists for that eventual migration but is currently unused.

The property `VlogClip.sourceCloudID` stores a `PHAsset.localIdentifier` despite the name — the "Cloud" prefix is a holdover from the original CloudKit plan.

### Temporary files

`FileManager.default.temporaryDirectory` is a cache for extracted Live Photo paired videos. These URLs are **never** persisted to SwiftData. They can be invalidated between launches.

---

## 4. Build & Test Commands

Prefer these over opening Xcode. Use them to verify your changes compile.

### Build for simulator

```bash
xcodebuild -scheme Madeleine \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
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

- Views end with `View` (e.g. `EditorView`)
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

- **EditorView**: bottom toolbar (share, play, orientation, add)
- **ContentView**: the "New Vlog" FAB (uses accent color background, not glass)

Pattern for grouped morphable buttons:

```swift
@Namespace private var glassNS

HStack(spacing: 24) {
    Button { ... } label: { Image(systemName: "play.fill").frame(width: 56, height: 56) }
    Menu { ... } label: { Image(systemName: "rectangle.portrait.rotate").frame(width: 56, height: 56) }
}
.padding(.horizontal, 6)
.glassEffect()
.glassEffectID("center", in: glassNS)
```

For a single interactive button:

```swift
Button { ... } label: { Image(systemName: "square.and.arrow.up").frame(width: 56, height: 56) }
    .glassEffect(.regular.interactive())
```

### 6.3 Rules

- **No nesting.** A `.glassEffect()` inside another `.glassEffect()` breaks visually.
- **No glass on content itself.** Glass is for floating chrome, not for photos/video.
- **Valid variants**: `.regular`, `.clear`, `.identity`. `.prominent` does NOT exist — do not hallucinate it.
- **Don't override sheet backgrounds.** `.presentationBackground(.clear)` etc. disables the new material.

---

## 7. SwiftData + CloudKit Rules

CloudKit sync is not currently enabled, but the `@Model` types follow the three CloudKit constraints below so the option remains open. Treat all three as mandatory when adding or modifying models.

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
├── MadeleineApp.swift              entry point, ModelContainer setup
├── Model/
│   ├── VlogProject.swift           @Model
│   └── VlogClip.swift              @Model
├── View/
│   ├── ContentView.swift           project list + NavigationStack root
│   ├── Extracting/
│   │   └── ExtractingView.swift    progress while extracting Live Photos
│   ├── Editor/
│   │   ├── EditorView.swift        Photos-app-style toolbar
│   │   ├── EditorViewModel.swift   @Observable
│   │   └── ClipTimelineView.swift  clip list with thumbnails
│   └── Preview/
│       └── PreviewView.swift       wraps AVKit VideoPlayer, auto-play
├── Service/
│   ├── CloudIdentifierResolver.swift   local ⇔ cloud ID conversion
│   ├── LivePhotoExtractor.swift        PHAsset → paired video URL
│   ├── VideoComposer.swift             [VlogClip] → AVComposition
│   ├── VideoExporter.swift             AVAssetExportSession wrapper
│   └── PhotoLibrarySaver.swift         save to Camera Roll, return cloudID
└── Assets.xcassets
    └── AccentColor (Golden Orange #F5A623)
```

---

## 11. Implementation Status

### Phase 1 — Foundation
- [x] Xcode project created with SwiftData + Host in CloudKit
- [x] Background Modes (Remote notifications) capability added
- [x] Info.plist: `NSPhotoLibraryAddUsageDescription`, `NSPhotoLibraryUsageDescription`
- [x] Deployment Target set to iOS 26.0
- [x] `MadeleineApp.swift` configured
- [x] Template `Item.swift` and `ContentView.swift` replaced

### Phase 2 — Models
- [x] `Model/VlogProject.swift`
- [x] `Model/VlogClip.swift`

### Phase 3 — Services
- [x] `Service/CloudIdentifierResolver.swift`
- [x] `Service/LivePhotoExtractor.swift`
- [x] `Service/VideoComposer.swift`
- [x] `Service/VideoExporter.swift`
- [x] `Service/PhotoLibrarySaver.swift`

### Phase 4 — Screens
- [x] `ContentView` (project list, accent-color FAB, NavigationStack)
- [x] PhotosPicker integration (with `photoLibrary: .shared()`)
- [x] `ExtractingView` (progress, error state with Go Back)
- [x] `EditorView` + `EditorViewModel` (Photos-app-style bottom bar)
- [x] `ClipTimelineView` (thumbnails, filenames, dates, swipe-delete, reorder)
- [x] `PreviewView` (auto-play, standard VideoPlayer controls)
- [x] Share sheet via `UIActivityViewController`

### Phase 5 — Polish
- [x] Empty states (no projects)
- [x] Non-Live Photo auto-removal during extraction
- [x] Accessibility labels on all icon buttons
- [x] Accent color (Golden Orange #F5A623)
- [x] Date-based default project titles
- [x] Orientation persistence per project
- [x] ModelContainer crash recovery
- [x] App icon
- [x] Privacy policy + About sheet
- [x] Per-clip crop preview sheet

---

## 12. Common Pitfalls

### Workflow
1. **New file → stop and ask the user first** (§8). Do not run `touch` or `Write` for new `.swift` files.
2. **Temporary URLs are never persisted.** If you need a reference that survives app launches, use an asset identifier.
3. **Design documents in `design/` use date-prefixed filenames** (e.g. `2026-04-19_color_compare.html`). The `docs/` directory is for the public site (GitHub Pages).

### CloudKit × SwiftData
4. Every `@Model` property needs a default or must be Optional (§7.1).
5. `@Relationship` must be defined on both sides (§7.2).
6. Do not use `@Attribute(.unique)` (§7.3).

### Photos
7. **Use `photoLibrary: .shared()` in PhotosPicker** to get `itemIdentifier`.
8. **`PhotosPickerItem.itemIdentifier` can be nil.** Skip items that have no identifier rather than crashing.
9. **Set `isNetworkAccessAllowed = true`** on `PHAssetResourceRequestOptions` — users may have source photos in iCloud but not on-device.
10. **Skip duplicate photos** when adding to an existing project (compare `sourceCloudID`).

### Media
11. **Apply `preferredTransform`** and normalize translation before scaling in `VideoComposer`.
12. **Mute audio for MVP.** Stitched one-second clips have audible cuts. Audio / BGM comes later.
13. **Trim from the center of each Live Photo.** The first ~0.5 s is usually motion blur.
14. **Clamp trim duration** to source video duration to avoid AVFoundation errors.

### Liquid Glass
15. **Do not nest `.glassEffect()`**. Use grouping within a single `.glassEffect()`.
16. **Do not apply glass to content itself** (photos, video frames, long text blocks).
17. **`.prominent` is not a valid variant.** Only `.regular`, `.clear`, `.identity` exist.
18. **Do not override sheet backgrounds.**

### UI Conventions
19. **No TabView** — single NavigationStack flow.
20. **ContentView is the root** — no separate HomeView.
21. **Button tint** — bottom toolbar uses `.tint(.primary)`, FAB uses accent color background.
22. **Date format** — `yyyy/MM/dd HH:mm:ss` for clip capture dates.

### Testing
23. **Simulator cannot capture Live Photos.** Test on a real device with existing Live Photos.

---

## 13. How to Work With the User

- When the user describes a feature, first confirm the scope, then implement one layer at a time (model → service → view).
- After each file change, run the build command (§4) before declaring success.
- If a build fails, fix errors yourself — do not ask the user to fix Swift compile errors unless you genuinely cannot.
- If a task requires a new file, UI asset, or capability change, stop and tell the user what to do in Xcode.
- Update §11 Implementation Status as you complete items.
- The user's other projects (Calories, Waffle, Shortcake) use `View/` + `ContentView` as root — follow this pattern.
