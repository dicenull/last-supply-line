# AI開発者向けの入口

このリポジトリは Godot 4.7 の戦車・工場構築ゲーム「M.F.V. 03 — 自走工廠 / 1918」。
具体的な手順・責務・既知の落とし穴は [AI開発フロー](docs/AI_DEVELOPMENT.md) を読む。
最新のユーザー指示を優先し、古い開発記録の仕様や検証件数を現在の状態と混同しない。

## 作業の進め方

- 作業開始時に `git status --short`、ブランチ、対象コードと関連テストを確認する。既存の未コミット変更を消さない。
- ユーザーへの説明は日本語で簡潔に。実装、検証、公開、pushのどこまで完了したかを区別する。
- **テストはヘッドレス、独立したものは最大4並列。** テストのためにGodotやChromiumのウィンドウを開かない。
- 「並列テスト」は複数テストプロセスを意味する。サブエージェントへの委任を意味しない。
- ユーザーの `run` はゲーム起動の依頼として扱う。テストのヘッドレス方針とは区別し、既存のプレイ中プロセスを勝手に終了しない。
- 実装中は必要な関連チェックを実施し、成功後の無目的な全件再実行を避ける。
- デプロイ・commit・pushは依頼・承認された範囲で実施する。すでに認められた操作を改めて確認しない。

## テストの標準コマンド

プロジェクト直下から実行する。Godotは `--godot` または `GODOT` 環境変数で変更できる。

```sh
python3 tools/run_tests.py --headless-only --jobs 4 --list
python3 tools/run_tests.py --headless-only --jobs 4 --timeout 90 \
  --suite responsive_footer --suite touch_controls --suite field_services \
  --suite footer_tools --suite loadout_ui --suite equipment_ui \
  --output build/ui-headless
```

- **引数なしの `tools/run_tests.py` はGUI試験も起動するので、標準運用では使わない。**
- `HEADLESS` / `VISUAL` / `SPECIAL` の最新分類は `tools/run_tests.py` が正。`VISUAL` の試験を名前だけ指定すると実ウィンドウが開く。
- 未対応のUI試験は描画待ち・画像取得をヘッドレス時に避け、操作と状態の検証を残してから分類を変更する。GUIを自動的な代替手段にしない。
- GodotヘッドレスはGPU外観・実音声出力の検証ではない。必要ならヘッドレスChromiumでWeb表示を検証し、未検証の範囲を明示する。
- 実行中はソースを変更しない。終了コード0、`summary.json` の `failures: 0` / `changed_sources: []`、エラー・リーク警告なしを確認する。
- 新しい `*_test.gd` はランナーに分類を登録する。テストごとにプロフィール・保存先・出力先を隔離する。

## 実装で守る仕様

- 修復はラインだけ。車体HPは回復しない。クリア時も同じ。
- 報酬・コンボ・所持品の変更は状態モデルで行う。UI・演出から二重に加算しない。
- 装備の強さは接続・配置・弾薬・燃料などのリスクリターンで作る。指定セット成立だけで付く連携ボーナスに戻さない。
- 初期装備も所持一覧にあり、装備なしも可能。旧装備IDと旧保存の復元を維持する。
- モデルは `item_model.gd` を共有する。レア度色は一部の識別部とフィールドの目印に使い、全面を塗り替えない。
- PC・スマホでメニューと操作の意味を統一する。Qは性能、Eは倉庫、Iは一覧。フッターの帯は設けず、下中央に建設アイコン、右端に操作アイコン、右下に丸い出撃ボタンを配置する。

## ファイルと配布

- `scripts/equipment_data.gd` 等の生成物は生成元と `tools/generate_equipment.py` から更新する。
- 新しいGodotスクリプトの `.uid`、必要なアセット・インポート設定を一緒に扱う。
- `build/`、`.godot/`、`node_modules/`、`.cloudflare/`、`.wrangler/` は作業成果物。commitしない。
- Webは `tools/export_web.py` で書き出してから `npm run deploy:web`。**deployコマンドだけではGodotソースを再書き出ししない。**
- 公開先は既存の `last-supply-line` Worker。公開後にHTML・PCKのサイズとSHA-256をビルドのmanifestと照合する。
- `TESTING.md` / `AUDIT.md` / `ROADMAP.md` の過去の成功件数は、現在のソースの検証結果ではない。
