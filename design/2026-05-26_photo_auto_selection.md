# Madeleine — 写真の自動セレクト機能 計画書 (v1)

## 1. 概要

旅行中に撮影した大量の Live Photo (例：500枚) から、Madeleine が自動で 30 枚前後を選び出して Vlog の素材にする機能を追加する。ユーザーは「いい感じに選んで」と指示するだけで、シーンの偏りなく・ブレや重複の少ない・構図の良いカットだけからなるクリップ列が生成される。

選定結果はそのまま編集画面 (`EditorView`) に流し込まれ、ユーザーは並び順や尺を最終調整できる。**自動セレクトは「下書き」であってユーザーの決定権は奪わない**、という位置づけ。

---

## 2. なぜやるか

現状の Madeleine は PhotosPicker で **手動選択 (最大30枚)** が前提。これには2つの摩擦がある:

1. **選ぶのが面倒** — 旅行の500枚から30枚を選ぶ作業は、それ自体が小さな編集行為で、心理的ハードルが高い
2. **選び方が均質になりにくい** — 序盤の写真ばかり選んでしまい、後半が薄くなる、似た構図を複数選んでしまう、ブレ写真を見落とす、など

iOS 26 / Vision フレームワークには `CalculateImageAestheticsScoresRequest` という写真品質スコアリング API があり、Apple 自身が「memorable な写真の選別」用途で導入したもの (WWDC24 Session 10163)。これを軸に複数の標準 API を組み合わせれば、Apple Intelligence の Memory Movie のような「自動キュレーション」を Madeleine の Vlog 生成フローに取り込める。

---

## 3. 採用技術と「不採用」の理由

### 3.1 採用

| API / Framework | 役割 |
|---|---|
| **`Vision.CalculateImageAestheticsScoresRequest`** (iOS 18+) | 写真の美的スコア (-1〜1) と `isUtility` フラグ。選定の主軸 |
| **`Vision.GenerateImageFeaturePrintRequest`** | 画像の特徴ベクトル。類似ショット (連写・ほぼ同じ構図) の重複排除 |
| **`Vision.DetectFaceCaptureQualityRequest`** | 人物写真の顔の写り (目つぶり・ボケ) で加点・減点 |
| **`Photos.PHAsset`** の `creationDate` / `location` | シーン (時間・場所) クラスタリング |
| **`Photos.PHPhotoLibrary`** Full access | 500枚規模を扱うため PhotosPicker ではなく直接フェッチ |
| **既存 `LivePhotoExtractor`** / **`VideoComposer`** | 選定後は既存パイプラインにそのまま接続 |

### 3.2 不採用 (調査済み)

| 候補 | 不採用の理由 |
|---|---|
| **Apple Intelligence Memory Movie 生成 API** | 公開 API なし。Photos アプリ内のユーザー操作からしか起動できない |
| **Foundation Models フレームワーク** (iOS 26) | テキスト専用のオンデバイス LLM。画像を直接スコアリングできない (Vision の出力を整形する用途であれば併用可能だが、選定の主軸にはならない) |
| **自前 Core ML モデル** | Vision の Aesthetics スコアが事実上 Apple 公式の置き換え版。再発明しない |
| **PHAssetCollection の Memories smart album** | iOS 側の curation 結果は読めるが、Madeleine の用途 (特定の旅行期間からピンポイントで) に合わない |

---

## 4. 入出力定義

### Input

ユーザーが次のいずれかで「自動セレクト対象」を指定する:

- **A案: 日付範囲** — 「2026/04/12 〜 2026/04/15 の Live Photo」
- **B案: PhotosPicker で大量選択** — 上限を 30 → 500 (もしくは無制限) に引き上げ、選定はその中から
- **C案: 写真アプリの「アルバム」を指定** — 旅行アルバムを作っているユーザー向け

**推奨は A**。理由：PhotosPicker は大量選択時の UI が重く、`itemIdentifier` の解決にも時間がかかる。日付範囲なら `PHFetchOptions.predicate` 一発で対象が確定する。B/C はオプションとして v1.1 以降で検討。

### Output

`[VlogClip]` の配列 (~30枚、既存の `VlogProject` にそのまま挿入可能)。各 `VlogClip` は:

- `sourceCloudID`: 選定された Live Photo の `PHAsset.localIdentifier`
- `order`: シーン順 (≒ 時系列)
- `trimDuration`: デフォルト値 (1.0秒)
- `trimStart`: nil (= 中央切り出し、既存規約通り)

---

## 5. パイプライン設計

500枚 → 30枚 を 5 ステージで絞り込む。各ステージは独立した actor / 関数として実装し、後で個別に差し替え可能にする。

```
[Stage 1] フェッチ
  PHAsset.fetchAssets(predicate: 日付範囲 AND mediaSubtype=photoLive)
       ↓ 500枚
[Stage 2] 軽量フィルタ
  - お気に入りなら加点ボーナス
  - PHAsset.pixelWidth/Height が極端に小さいものを除外
       ↓ ~500枚 (ほぼ通過)
[Stage 3] シーンクラスタリング
  creationDate (15分以内) + location (100m以内) でグループ化
       ↓ N シーン (典型的に 15〜40)
[Stage 4] シーン内品質評価
  各 PHAsset に対し並列で:
    - CalculateImageAestheticsScoresRequest → overallScore, isUtility
    - GenerateImageFeaturePrintRequest → featureVector
    - 顔が含まれる場合 DetectFaceCaptureQualityRequest → faceQuality
  isUtility=true は即除外
       ↓
[Stage 5] 配分 & 重複排除
  シーンごとに枠を割り振り (例: ceil(30 / sceneCount) +α)
  シーン内では:
    1. 美的スコア降順にソート
    2. 上位から順に採用、ただし feature print の距離が閾値未満のものはスキップ
    3. シーン枠を満たしたら次のシーンへ
       ↓ ~30枚
[Stage 6] VlogClip 化
  時系列でソート (creationDate 昇順) → order 番号付与 → 返す
```

### 設計判断メモ

- **時間・場所クラスタの閾値 (15分 / 100m)** は v1 ではハードコード。後でユーザー設定にする余地あり。位置情報を持たない写真は時間のみでクラスタ化
- **顔品質スコア**は人物写真のみに使う。`VNDetectFaceRectanglesRequest` で顔の有無を先に判定
- **最終枠数 (30) はユーザー指定可能**にする。スライダーで 10〜50 程度
- **位置情報なし写真**は時間で別シーンを作るのが安全。地理クラスタの方は別扱い
- **Live Photo 以外** (通常静止画) は Stage 1 でフィルタ済みなので考えなくてよい (Madeleine の前提に合わせる)

---

## 6. データモデル変更

### 6.1 追加が必要なもの

`VlogProject` に「自動選定で作られたか」フラグ + 選定パラメータの記録があると、再選定や UI 表示で便利。

```swift
@Model
final class VlogProject {
    // 既存プロパティ...

    /// 自動セレクト由来かどうか
    var isAutoSelected: Bool = false

    /// 自動セレクト時のパラメータ (再実行用)
    var autoSelectFromDate: Date?
    var autoSelectToDate: Date?
    var autoSelectTargetCount: Int = 30
}
```

CloudKit 制約 (§7) に従って全て初期値あり / Optional。

### 6.2 `VlogClip` は変更不要

`sourceCloudID` (= `PHAsset.localIdentifier`) と `order` だけあれば既存パイプラインに接続できる。スコア情報は永続化しない (再選定で再計算可能なので持たない方が綺麗)。

---

## 7. UI 設計

### 7.1 エントリポイント

`ContentView` (プロジェクト一覧画面) の FAB を「+」単一からアクションシート展開に変える:

```
[FAB タップ]
   ↓
┌─────────────────────────┐
│ + 写真を選んで作る (現状)  │
│ ✨ 旅行から自動で選ぶ (新規)│
│ × キャンセル              │
└─────────────────────────┘
```

「自動」を選ぶと **`AutoSelectSetupView`** (新規) に遷移。

### 7.2 新規画面: AutoSelectSetupView

シンプルな入力フォーム:

- 日付範囲ピッカー (`DatePicker` 2つ、`.dateRange` graphical style)
- 「枚数」スライダー (10〜50)
- 「セレクト開始」ボタン

### 7.3 新規画面: AutoSelectingView

`ExtractingView` と同じ位置づけの進捗画面。多段階処理なのでステージ表示があると親切:

```
旅行から最高の瞬間を選んでいます…

[████████░░░░░░] 60%
"クリップの品質を評価中" (Stage 4)
```

完了したら既存の `EditorView` に遷移。ユーザーは順序・尺を最終調整できる。

### 7.4 Liquid Glass

新規画面とも標準コンポーネント (`NavigationStack`, sheet, partial-height sheet) を使うので、Liquid Glass は自動適用される。`AutoSelectingView` で進捗バーの上に浮く「キャンセル」ボタンに `.glassEffect(.regular.interactive())` を使う程度。

### 7.5 権限

PhotosPicker と違い、Stage 1 のフェッチには **Full Photo Library Access** が必要。`PHPhotoLibrary.requestAuthorization(for: .readWrite)` を初回呼び出し時に要求。`Info.plist` の `NSPhotoLibraryUsageDescription` は既存のものをそのまま使えるが、文言を「自動セレクトのため写真ライブラリを参照します」にアップデートするか検討。

---

## 8. 主要サービスの骨格

### 8.1 SceneClusterer (新規, struct)

```swift
struct SceneClusterer {
    let timeGapThreshold: TimeInterval = 15 * 60   // 15分
    let distanceThreshold: CLLocationDistance = 100 // 100m

    /// PHAsset の配列を「シーン」グループに分割
    func cluster(_ assets: [PHAsset]) -> [[PHAsset]] {
        let sorted = assets.sorted { ($0.creationDate ?? .distantPast) < ($1.creationDate ?? .distantPast) }
        var scenes: [[PHAsset]] = []
        var current: [PHAsset] = []

        for asset in sorted {
            if let last = current.last, shouldSplit(from: last, to: asset) {
                scenes.append(current)
                current = []
            }
            current.append(asset)
        }
        if !current.isEmpty { scenes.append(current) }
        return scenes
    }

    private func shouldSplit(from a: PHAsset, to b: PHAsset) -> Bool {
        guard let dA = a.creationDate, let dB = b.creationDate else { return false }
        if dB.timeIntervalSince(dA) > timeGapThreshold { return true }
        if let lA = a.location, let lB = b.location,
           lA.distance(from: lB) > distanceThreshold { return true }
        return false
    }
}
```

### 8.2 ImageQualityScorer (新規, actor)

```swift
import Vision
import Photos

actor ImageQualityScorer {
    struct Score: Sendable {
        let assetID: String
        let aesthetic: Float      // -1...1
        let isUtility: Bool
        let faceQuality: Float?   // 0...1, 顔がある場合のみ
        let featurePrint: VNFeaturePrintObservation?
    }

    func score(_ asset: PHAsset) async throws -> Score {
        let image = try await loadCGImage(for: asset)

        async let aesthetics = runAesthetics(image)
        async let featurePrint = runFeaturePrint(image)
        async let faceQuality = runFaceQuality(image)

        let (a, fp, fq) = try await (aesthetics, featurePrint, faceQuality)
        return Score(
            assetID: asset.localIdentifier,
            aesthetic: a.overallScore,
            isUtility: a.isUtility,
            faceQuality: fq,
            featurePrint: fp
        )
    }

    // private: PHImageManager → CGImage 変換 + 各 Vision request の実装
}
```

並列化のポイント:
- 1 アセット内では 3 種の Vision request を `async let` で並列
- アセット間は `TaskGroup` で並列化 (ただし同時実行数を制限。デフォルトで `ProcessInfo.processInfo.activeProcessorCount` 程度)

### 8.3 AutoCurator (新規, actor)

パイプライン全体のオーケストレータ。`SceneClusterer` と `ImageQualityScorer` を呼んで `[VlogClip]` を返す。進捗をストリームで報告:

```swift
actor AutoCurator {
    struct Progress: Sendable {
        let stage: Stage
        let percent: Double
    }
    enum Stage { case fetching, scoring, selecting }

    func curate(
        from: Date,
        to: Date,
        targetCount: Int,
        progress: @Sendable @escaping (Progress) -> Void
    ) async throws -> [VlogClip] {
        // Stage 1: fetch
        // Stage 2: lightweight filter
        // Stage 3: cluster
        // Stage 4: score (並列, 進捗報告)
        // Stage 5: allocate + dedupe
        // Stage 6: → [VlogClip]
    }
}
```

---

## 9. パフォーマンス

500枚 × 3種 Vision request の処理時間が問題になる。実機 (iPhone 17 Pro 等の Apple Silicon 想定) での見込み:

| 処理 | 1枚あたり目安 | 500枚 (8並列) |
|---|---|---|
| Aesthetics | ~50ms | ~3秒 |
| Feature Print | ~30ms | ~2秒 |
| Face Quality (条件付き) | ~40ms | ~2秒 |
| **CGImage 読み出し** (PHImageManager から低解像度版) | ~80ms | ~5秒 |
| **合計** | — | **15〜30秒程度** |

iCloud 写真がオンデバイスにない場合はネットワーク経由のダウンロードが入って大きく伸びる。`PHImageRequestOptions.isNetworkAccessAllowed = false` でまずローカル版だけ使う、と決めるのが安全 (Vision 用には低解像度版で十分)。

並列度はメモリ次第。`TaskGroup` での同時実行数を 4〜8 にクランプし、`autoreleasepool` で CGImage を都度解放する。

---

## 10. 段階的な実装ロードマップ

ファイルは事前に Xcode GUI で空ファイル作成 (§8 ルール)。各 Step ごとにビルドが通ることを確認。

### Step 1: モデル拡張
- [ ] `VlogProject.swift` に `isAutoSelected`, `autoSelectFromDate`, `autoSelectToDate`, `autoSelectTargetCount` を追加
- [ ] CloudKit 制約に準拠 (初期値あり / Optional) を確認
- [ ] ビルドが通り、既存プロジェクトデータが破壊されないことを確認 (SwiftData migration)

### Step 2: SceneClusterer
- [ ] `Service/SceneClusterer.swift` (空ファイルを Xcode で作成 → Claude が中身)
- [ ] ユニットテスト相当の動作: 既存プロジェクト一覧の写真でクラスタ分割を `print` 確認 (実機)

### Step 3: ImageQualityScorer
- [ ] `Service/ImageQualityScorer.swift`
- [ ] Aesthetics, FeaturePrint, FaceQuality 3種の Vision request 実装
- [ ] 単一アセットでスコアが返るところまで実機確認

### Step 4: AutoCurator
- [ ] `Service/AutoCurator.swift`
- [ ] パイプライン全体を組み上げ、`[VlogClip]` を返す
- [ ] 進捗報告 (closure or AsyncStream)

### Step 5: AutoSelectSetupView
- [ ] `View/AutoSelect/AutoSelectSetupView.swift`
- [ ] 日付範囲 + 枚数スライダー + 開始ボタン

### Step 6: AutoSelectingView
- [ ] `View/AutoSelect/AutoSelectingView.swift`
- [ ] 進捗バー + ステージテキスト + キャンセル

### Step 7: ContentView 統合
- [ ] FAB をアクションシート展開に
- [ ] 新規フロー: SetupView → SelectingView → EditorView

### Step 8: 仕上げ
- [ ] Full Photo Library Access の permission UX
- [ ] エラーハンドリング (権限なし / 該当写真ゼロ / 全部 utility 判定 etc.)
- [ ] EditorView から「自動セレクトをやり直す」導線 (パラメータ記憶を活用)

---

## 11. オープン課題 (実装中に決める)

1. **シーン枠の配分式** — 単純な均等割か、シーン内写真数で重み付けか。実データで試して決める
2. **重複排除の距離閾値** — `VNFeaturePrintObservation.computeDistance(_:to:)` の値はモデル依存。実機で実験して 0.5〜0.8 あたりから攻める
3. **顔品質スコアの寄与度** — Aesthetics スコアと単純合算か、別軸で「最低限の顔品質しきい値」フィルタにするか
4. **位置情報なし旅行** (iCloud 写真の場所がオフ等) のクラスタリングを時間のみに fallback したときの体感品質
5. **PhotosPicker フローも残すか** — 既存の手動選択を残しつつ「自動」を追加で増やす想定だが、UI 上どちらを主にするか
6. **再選定時のシード** — 同じパラメータで再選定すると同じ結果になるが、「もう一度別の組み合わせを見たい」需要があるか

---

## 12. 落とし穴チェックリスト

### Vision / Photos
1. **`PHImageManager` の `requestImage` は同期コールバックが複数回呼ばれる** — 低品質版 → 高品質版で2回。`continuation.resume` は1回しか呼べないので `info[PHImageResultIsDegradedKey]` で判定するか、`deliveryMode = .opportunistic` を避けて `.highQualityFormat` か `.fastFormat` を明示する
2. **iCloud 未ダウンロードの写真** — Stage 4 では `isNetworkAccessAllowed = false` にしてローカルだけで判定。それで取れないアセットは「評価不能」として除外
3. **`VNGenerateImageFeaturePrintRequest` のリビジョン**を固定する (`request.revision = VNGenerateImageFeaturePrintRequestRevision2` 等)。リビジョンが違う特徴量は距離計算できない

### Concurrency
4. **`TaskGroup` の並列数を制限** — 500件を全部並列にすると OOM の危険。`maxConcurrent = 4〜8`
5. **`ImageQualityScorer` は actor**、`SceneClusterer` は stateless なので struct
6. **キャンセル可能に** — `Task.checkCancellation()` を Vision request の前後に挟む

### CloudKit × SwiftData
7. 既存 `VlogProject` にプロパティ追加するときは、すべて初期値あり or Optional (§7.1 準拠)
8. SwiftData の自動 migration が効くか確認 (CloudKit 同期は無効なので比較的安全)

### UX
9. **「自動セレクトをやり直す」と既存クリップを上書きするか** — ユーザーが手動で並べ替えた結果を消すのは危険。「新規プロジェクトとして再生成」を基本にする
10. **権限を「すべての写真へのアクセス」に上げる必要がある** — 既存ユーザーが「選択した写真のみ」許可している可能性。permission ダウングレード時のフォールバック (= 機能を無効化) を用意

### Liquid Glass
11. **進捗バーにガラスをかけない** — コンテンツそのものはガラス対象外 (§6.3)

---

## 13. 参考リンク

- [CalculateImageAestheticsScoresRequest — Apple Developer Documentation](https://developer.apple.com/documentation/vision/calculateimageaestheticsscoresrequest)
- [Discover Swift enhancements in the Vision framework — WWDC24 Session 10163](https://developer.apple.com/videos/play/wwdc2024/10163/)
- [GenerateImageFeaturePrintRequest — Apple Developer Documentation](https://developer.apple.com/documentation/vision/generateimagefeatureprintrequest)
- [DetectFaceCaptureQualityRequest — Apple Developer Documentation](https://developer.apple.com/documentation/vision/detectfacecapturequalityrequest)
- [PhotoKit — Apple Developer Documentation](https://developer.apple.com/documentation/photokit)
- 既存計画書 [`2026-04-18_Madeleine_design.md`](./2026-04-18_Madeleine_design.md)
