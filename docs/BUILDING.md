# 起動・ビルド

[READMEへ戻る](../README.md)

以下のコマンドは、特に指定がなければプロジェクト直下で実行します。

## ローカルで起動

macOSのGodot 4.7.2 / Compatibilityで検証しています。追加アドオン・外部モデルは不要です。

macOSの標準配置では、プロジェクト直下で次のコマンドを実行します。

```sh
/Applications/Godot.app/Contents/MacOS/Godot --path .
```

別の環境ではGodot実行ファイルのパスを置き換えてください。別のフォルダから実行する場合は、`--path`にプロジェクトフォルダを指定します。パスに空白がある場合は、そのパスをダブルクォートで囲みます。

Godotエディターから起動する場合：

1. Godot 4.7のプロジェクトマネージャーで、このフォルダの `project.godot` をインポートして開きます。
2. 初回のインポート処理が終わったら、右上の実行ボタンまたは **F5** で起動します。

## Web版

ブラウザ版のビルド・ローカル起動・Cloudflare Workersへの公開は[Web版の手順](../web/README.md)を参照してください。

## ゲームデータの書き出し

次の手順はGodot 4.7でPCKを書き出し、空の作業フォルダから起動・生産・射撃・走行を自動確認します。

~~~sh
python3 tools/export_pack.py --godot /Applications/Godot.app/Contents/MacOS/Godot
~~~

出力はbuild/mfv03.pckと検証情報・SHA-256を含むbuild/mfv03-manifest.jsonです。試験コード・プレビュー画像・作業用ツールはPCKに含めません。PCKはGodotランタイムが必要なゲームデータで、単体アプリではありません。

~~~sh
/Applications/Godot.app/Contents/MacOS/Godot --main-pack /absolute/path/to/mfv03.pck
~~~

macOSの書き出しプリセットも付属します。単体アプリの書き出し・実行確認は対応する書き出しテンプレートの導入後に行います。現時点では署名や公証を行っていません。

## macOS単体アプリの書き出し

Godot 4.7.2の公式Export Templatesを導入し、次を実行します。

~~~sh
python3 tools/export_macos.py --godot /Applications/Godot.app/Contents/MacOS/Godot
~~~

build/MFV03.zipに、Apple Silicon・Intel両方の実行ファイルを含むアプリを生成します。展開したAMMO LINE LAB.appはGodotエディターを別途必要としません。内部名は既存の保存先との互換性のため維持しています。

ビルドは一時フォルダへ展開し、ソースを参照しない画面なし／画面あり起動を検証します。mfv03-macos-manifest.jsonにGodot版、コミット、変更有無、SHA-256を記録。署名・公証なしのローカル試作版です。Intel側は実行ファイルの同梱のみ確認し、実機動作はApple Siliconで検証しています。

## 検証

テストの実行方法と検証範囲は[TESTING.md](../TESTING.md)、過去の監査結果は[AUDIT.md](../AUDIT.md)を参照してください。
