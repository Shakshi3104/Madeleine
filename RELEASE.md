# Release Guide

Madeleine のリリースは [`asc`](https://github.com/rorkai/App-Store-Connect-CLI) (App Store Connect CLI) でローカル完結します。Xcode の Organizer 操作は不要です。

---

## セットアップ(初回のみ)

### 1. asc CLI をインストール

```bash
brew install asc
```

### 2. App Store Connect API キーを準備

1. https://appstoreconnect.apple.com/access/integrations/api でチームキーを生成(Admin 権限)
2. `.p8` ファイルを `~/.appstoreconnect/AuthKey_XXX.p8` に保存(`chmod 600`)
3. Issuer ID / Key ID を控える

### 3. 認証情報を .env に登録

`.env.example` をコピーして `.env` を作成し、値を埋める:

```bash
cp .env.example .env
# エディタで .env を編集して ASC_KEY_ID / ASC_ISSUER_ID / ASC_PRIVATE_KEY_PATH / ASC_APP_ID を入力
```

`.env` は `.gitignore` 済みなのでコミットされません。

### 4. App Store Connect の Test Information を GUI で埋める(External 配信する場合のみ)

External Testing で Beta App Review に提出するには、**ビルドとは別にアプリ単位のメタデータ**を事前に登録しておく必要があります。これは `asc` のスコープ外(現状の asc には対応コマンドがない)で、初回だけ GUI 操作が必要です。

App Store Connect → Madeleine → TestFlight → **テスト情報** で以下を保存:

- **ベータ版アプリの説明 (Beta App Description)** — アプリ全体の説明。バージョンを跨いで使い回されます
- **フィードバックメールアドレス** — `shakshi3104.support@icloud.com`

埋めずに `testflight_external` を実行すると、最後の publish ステップで `Beta App Description is required to submit a build for external testing.` で落ちます(その時点で IPA のアップロードと Beta Group への attach までは完了している状態)。

> **What to Test(テスト内容)はビルド単位**
>
> ベータ版アプリの説明と違い、What to Test はビルドごとに最低 1 ロケール必須。デフォルトでは GUI で手入力しますが、ワークフローから自動入力したい場合は `.asc/workflow.json` の `publish` ステップに `--test-notes "..." --locale en-US` を追加することで API 経由で書けます。

---

## リリース手順

毎回のリリースで実行する流れ。

### 認証情報を読み込む

```bash
set -a; source .env; set +a
```

### Internal Testing(自分や組織メンバーのみ、即配信)

```bash
asc workflow run testflight_internal VERSION:1.0
```

archive → IPA エクスポート → アップロード → 処理完了待ち を 1 コマンドで実行。Internal Tester(App Store Connect の Users and Access に登録されたユーザー)に自動的に届きます。

### External Testing(社外テスター、Beta App Review が必要)

```bash
asc workflow run testflight_external VERSION:1.0 GROUP:"Madeleine Tester"
```

archive → IPA エクスポート → アップロード → 指定 Beta Group へ配信 → Beta App Review 提出 を 1 コマンドで実行。

`GROUP` は App Store Connect で作成した External Beta Group の名前 or ID を渡します。

### 同じ Version の再ビルド(再審査不要)

`SUBMIT_BETA:false` で審査提出をスキップ:

```bash
asc workflow run testflight_external VERSION:1.0 GROUP:"Madeleine Tester" SUBMIT_BETA:false
```

Beta App Review は **Marketing Version ごとに 1 回**通れば、同 Version の build 番号違いはそのまま配信できます。

---

## ビルド番号の運用

`CFBundleVersion` は `Madeleine.xcodeproj` の Run Script build phase で `git rev-list --count HEAD` の値に自動的に書き換わります。手動で更新する必要はありません。

- ソースの `Info.plist` は常に `1` のまま据え置き(git diff が出ないように)
- 成果物バンドル(`Madeleine.app/Info.plist`)だけが書き換わる
- コミットが進む = ビルド番号が増える、なので TestFlight への再アップロードが弾かれない

---

## トラブルシュート

### `Error: --group is required`

`asc publish testflight` には Beta Group が必須。Internal Testing の場合は `asc builds upload`(workflow 内では `testflight_internal` ステップ)を使う。

### `Beta App Description is required to submit a build for external testing.`

App Store Connect 側のアプリ単位メタデータ(ベータ版アプリの説明 / フィードバックメールアドレス)が未入力。セットアップ §4 を参照して GUI で 1 度だけ埋める。

このエラー時点で IPA のアップロードと Beta Group への attach は成功しているので、GUI 入力後に新規ビルドを作り直す必要はなく、エラー出力に表示される resume コマンドで publish ステップだけリトライできる:

```bash
asc workflow run --file '.asc/workflow.json' 'testflight_external' --resume '<run-id>'
```

`<run-id>` は `.asc/runs/` 配下の最新ファイル名から取れる(`testflight_external-YYYYMMDDTHHMMSSZ-xxxxxxxx`)。

### `Error Opening Destination: [Operation not permitted]`

Run Script の sandbox が `.git/` 読み or `Info.plist` 書きをブロックしている。プロジェクト設定で `ENABLE_USER_SCRIPT_SANDBOXING = NO` になっているか確認(設定済み)。

### `アクセス権をリクエスト` 画面が出る(App Store Connect API)

個人アカウントでも初回は組織レベルで API アクセスを有効化する必要がある。ボタンを押せば即時 or メール確認を経て有効化される。

---

## App Store 本申請

別途準備が必要。Beta App Review とは別審査(通常 1〜3 日):

- スクリーンショット(6.9" / 6.7" / iPad 対応サイズ)
- 説明文(4000字)・サブタイトル(30字)・キーワード(100字)・プロモテキスト(170字)
- 年齢レーティング
- App Store Connect の「App プライバシー」設定
- カテゴリ(Madeleine は Photo & Video)

これらは TestFlight 配信とは独立しているため、TestFlight で使っているビルドをそのまま「リリースに追加」して提出できます。
