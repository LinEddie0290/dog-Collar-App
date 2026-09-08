# UI側 セットアップ手順 (app_lib_dropin の使い方)

`packages/collar_data`（データ層、完成済み）の上に、画面（UI）を足すための手順です。
UIのコードは `app_lib_dropin/` に**仮置き**してあります。これは `flutter create` が
まだ実行されておらず、この時点では `lib/` フォルダ自体がリポジトリに存在しないためです。

## 1. Flutterプロジェクトの土台を作る（リポジトリのルートで）

```bash
flutter create --project-name collar_app .
```

`--project-name` を付けているのは、フォルダ名 `dog-Collar-App-main` がそのままだと
Dartのパッケージ名として使えない文字（大文字・ハイフン）を含んでいるためです。
`packages/` と `INTEGRATION.md` はこのコマンドで変更されません。

## 2. 仮置きしていたUIコードを本来の場所に移す

```bash
rm -rf lib
cp -r app_lib_dropin/lib ./lib
rm -rf app_lib_dropin
```

## 3. pubspec.yaml に依存関係を追加する

生成された `pubspec.yaml` の `dependencies:` の下に、以下の2つを追記します。

```yaml
dependencies:
  flutter:
    sdk: flutter
  collar_data:
    path: packages/collar_data
  path_provider: ^2.1.1
```

## 4. 取得してビルド確認

```bash
flutter pub get
flutter analyze
```

## 5. 実行

シミュレータ/実機なら `FakeCollarDataSource`（アプリ内モック）でそのまま動きます。
`tools/mock_collar.dart` は、実際に WebSocket 経由で疎通確認したいときに使う、
別プロセスのにせ首輪サーバーです（`dart run tools/mock_collar.dart`）。

```bash
flutter run
```

## この構成でやっていること

- `lib/ui/home_page.dart` は `package:collar_data` の `CollarRepository` /
  `SensorSample` / `ConnStatus` だけを見ていて、ソケットやJSON、フィルタの中身は
  一切知りません（そこは全部 `packages/collar_data` 側の責任）。
- mock ⇔ 実機の切り替えは `FakeCollarDataSource` ⇔ `WebSocketCollarDataSource`
  を差し替えるだけで、UI側のコードは変わりません。
