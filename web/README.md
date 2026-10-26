# Web版 / Cloudflare Workers

公開URL: https://last-supply-line.dicenull-dev.workers.dev

Godot 4.7.2のCompatibility / シングルスレッド版を、Cloudflare Workers Static Assetsで配信する。
WASMの圧縮済みレスポンスだけを小さなWorkerで返し、その他は静的配信する。サーバー側のゲーム処理、データベース、Pagesは使用しない。保存先は各ブラウザのIndexedDB。

日本語は同梱のNoto Sans JPを使う。ゲーム内はWeb専用の共通テーマでツールチップを含む標準UIへ適用し、Webページ側も同じフォントのWOFF2を自サイトから配信する。OSの日本語フォントや外部フォントCDNには依存しない。ライセンスは `NotoSansJP-LICENSE.txt` に同梱。`npm run test:web:font` でPC・タッチを並列確認できる。

## 初回準備

1. [Godot公式4.7.2のエクスポートテンプレート](https://godotengine.org/download/archive/4.7.2-stable/)を取得する。
2. TPZ（ZIP形式）の`templates/web_nothreads_release.zip`を取り出す。
3. Node.js 22.18以降でプロジェクト直下から`npm ci`を実行する。

```sh
python3 tools/export_web.py \
  --godot /Applications/Godot.app/Contents/MacOS/Godot \
  --template /path/to/web_nothreads_release.zip
```

テンプレートは`build/web-templates`へコピーする。次回以降は`--template`を省略できる。
使用するGodot本体とテンプレートは同じバージョンにそろえる。

## ビルドとローカル確認

```sh
python3 tools/export_web.py --godot /Applications/Godot.app/Contents/MacOS/Godot
npm run dev:web
```

cfが表示したローカルURLを開く。`build/web/index.html`の直接ダブルクリックでは起動しない。
`index.wasm.gz`はgzip圧縮済み。`web/worker.js`が`/index.wasm`への応答に`Content-Encoding: gzip`と`encodeBody: "manual"`を付け、二重圧縮を防ぐ。
単純な`python -m http.server`ではなく、cfで確認する。

`build/MFV03-web.zip`に静的ファイル一式（配信にはリポジトリ内のWorker設定と`web/worker.js`も必要）、`build/mfv03-web-manifest.json`に各ファイルのハッシュを記録する。
WASMを圧縮してWorkersの1ファイル25 MiB制限に収め、全ファイルのサイズもビルド時に検査する。
出力フォルダにはゲーム用ファイルとフォントライセンスだけを置き、テスト・ソース・ログ・認証情報を配信しない。

## 公開

```sh
npx cf auth login
npm run check:deploy
npm run deploy:web
```

`cloudflare.config.ts`のWorker名は`last-supply-line`。認証したCloudflareアカウントの`workers.dev` URLへ公開する。
複数アカウントがある場合は、公開対象を選んでから実行する。同名の既存Workerがある場合は、更新先がこのゲームであることを確認する。
独自ドメインの指定やDNS変更は行わない。

設定は`cloudflare.config.ts`、静的ファイルの場所などのビルド設定は`wrangler.config.ts`。`npm run dev:web` / `check:deploy` / `deploy:web`はいずれもcfを使用する。

## ブラウザ検証

```sh
# 別ターミナルで npm run dev:web を実行した状態で
WEB_URL=http://127.0.0.1:8791 npm run test:web
```

初回は`npx playwright install chromium`で検証用ブラウザを導入する。Godotが標準パスにない場合は`GODOT=/path/to/Godot`を指定する。隔離したブラウザで日本語表示・実入力・走行音・生産・移動・装備のドラッグ配置・個別解体・一括解体の確認とキャンセル・保存・再読込・再開を確認し、`build/web-audit`へ画面と結果を保存する。

## ブラウザでの操作

PCはキーボードとマウス、スマホは横持ちのタッチ操作を使用する。Godotの `InputEventScreenTouch` / `InputEventScreenDrag` で移動パッドと複数指操作を処理し、既存UIのタップはGodotのマウスエミュレーションを使用する。Web独自のゲーム操作ブリッジは使用しない。

スマホでは左パッドの上下で前後進、左右で旋回。画面下はPCと同じカテゴリタブ・設備・操作アイコンを使い、狭い画面では3段へ並べ替える。カテゴリから設備を選んで設置し、回転・撤去・収納・装甲・倉庫・視点・出撃／停止・メニューも共通アイコンで操作する。戦場では操作の1段だけを表示し、移動パッドと重ならない。倉庫の装備をタップしてから設置位置をタップすると配置できる。車体パーツの行は換装操作になる。メニューと倉庫はPCと同じ1列・アイコン表示を使う。倉庫は1ページ6個で、狭い画面では表示倍率を調整し、高さが足りない部分はGodotのスクロール領域で操作する。装備変更はPC同様に出撃準備中のみ。

タイトル・設定・履歴などのメニューは縦向きでも利用できる。戦闘中に縦向きへ回転すると一時停止メニューを開く。横向きに戻してから再開する。ブラウザが対応していれば右上から全画面表示にできる。
音声は最初のクリック／キー操作後に有効になる。「終了」の代わりに「保存してタイトルへ」を表示する。
タブを閉じる前にEscメニューの「ランを保存」または「保存してタイトルへ」を使う。
ブラウザのデータ削除やプライベートモードでは保存が保持されない場合がある。
ブラウザや公開ドメインが異なるとセーブデータは共有されない。macOS版のセーブとは別。

スマホ相当のブラウザ検証は `npm run test:web:touch`。844×390のChromiumタッチエミュレーションで、実タッチによる装備配置・収納・走行・2本指での停止・IndexedDB保存と再開・縦向きでの停止を確認する。PC用 `npm run test:web` と別プロセスで並列実行できる。Android / iPhone実機の検証とは区別する。`npm run test:web:responsive` は同じ390×844・844×390の画面でマウスとタッチのメニュー操作を並列確認する。

## 公式資料

- [Godot: Exporting for the Web](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_web.html)
- [Godot: SystemFontの対応環境](https://docs.godotengine.org/en/stable/classes/class_systemfont.html)
- [Cloudflare: Static Assets](https://developers.cloudflare.com/workers/static-assets/)
- [Cloudflare: 配信ヘッダー](https://developers.cloudflare.com/workers/static-assets/headers/)
- [Cloudflare: Static Assetsの容量制限](https://developers.cloudflare.com/workers/platform/limits/#static-assets)

## 検証記録（2026-10-22）

換装UIのブラウザ検証は、先に `python3 tools/run_tests.py --jobs 4 --suite loadout_ui` で専用セーブを生成し、`npm run test:web:loadout` を実行する。スマホ相当は `TOUCH=1` を付ける。`WEB_URL` と `WEB_AUDIT_DIR` で接続先・証跡先を指定できる。テスト専用のブラウザコンテキスト内でのみセーブを差し替え、4部位の実クリック換装・エンジン交換・再読込を検証する。

ローカルと公開URLの両方で、Chromium 149の実描画19項目が成功。1440×940と960×628を目視確認。音声波形、実生産、W移動、IndexedDB保存、ページ再読込、停止状態での復帰、保存してタイトルへ戻る操作を確認した。デスクトップのメニュー回帰21項目も成功。Safari・Firefox・スマートフォンは今回の実機検証対象に含めない。

### 換装クリック修正・雑魚石炭ドロップ版の公開（2026-10-26）

換装ボタンが毎フレーム無効→有効へ切り替わり、押下中のクリックをキャンセルしていた不具合を修正。ボタンの最終状態を一度だけ設定する。瞬間的なクリックでは発見できなかったため、ネイティブ検証に押下中の複数回UI更新、Web検証に120ms保持するマウス・タッチ入力を追加した。修正前のWebビルドで失敗を再現し、修正後はPC20項目・タッチ18項目、関連Godot356項目が成功。

雑魚敵は既存の廃材に石炭1個を加えて地面へドロップし、近づくと回収する。物資輸送車の石炭4個は維持。地面の素材・近接回収・保存復帰・二重取得防止を含むGodot707項目が成功。独立テストは並列実行した。

公開Workerバージョンは `1ba99b1f-4a1c-41a6-a0b1-bde65b4c194e`。証跡は `build/swap-browser-before`、`build/swap-press-final`、`build/swap-web-desktop`、`build/swap-web-touch`、`build/grunt-coal`。公開HTML / PCKの一致は `build/swap-coal-deployment.json` に記録。

### 左端装備パネル・構築カメラ・装備なし版の公開（2026-10-26）

装備中パネルを画面左端、倉庫を右端へ配置。ライン構築画面ではWASDをカメラの平行移動に使い、戦場画面では従来どおり車体を操作する。4部位は標準装備も取り外して倉庫へ保管でき、装備なし専用の取付台・主砲口・履帯を外した車輪を表示する。主砲なしでは射撃できず、駆動系が欠けると走行できない。保存形式13で空部位とカメラ移動量を保持し、旧保存は標準装備を維持する。スマホの全画面ボタンは左右パネルの間へ移動。

Workerバージョンは `44374264-4efe-4cd5-be0c-a7ce44b1782e`。独立テストを並列実行し、Godot 11スイート2,519項目、ローカルWebのPC20項目・タッチ17項目が成功。公開先では全画面ボタンの非重複を含むタッチ18項目が成功。証跡は `build/empty-loadout-validation.json`、`build/empty-web-desktop`、`build/empty-web-mobile`、`build/empty-production-mobile`。公開HTML / PCKの一致は `build/empty-loadout-deployment.json`。スマホはChromiumのタッチエミュレーション。

### 換装・車体外観・設置装備回転版の公開（2026-10-26）

倉庫を設置物と4部位のタブへ整理し、左ペインに装備中パーツと実効性能を表示。選択と換装を別操作にし、旧パーツは自動で倉庫へ戻す。ギア・エンジン・履帯・主砲の外観と品質色を即時反映し、主砲の追加部品は旋回と反動に追従する。設置物は90度回転、選択／設置状態の表示と向きの保存に対応。スマホの全画面ボタンを左上へ移し、倉庫の閉じる操作との重なりを解消した。

Workerバージョンは `0245d5c8-715f-4747-8d84-42bc998907b6`。関連Godot 12スイート2,595項目、ローカルWeb 43項目、公開先のタッチ換装12項目が成功。独立テストは並列実行し、画面を共有するネイティブ描画テストのみ直列化。証跡は `build/loadout-validation.json`、`build/loadout-web-desktop-verified`、`build/loadout-web-mobile-final`、`build/rotation-web-touch`、`build/loadout-production-mobile`。公開HTML / PCKの一致は `build/loadout-deployment.json` に記録。スマホ検証はChromiumのタッチエミュレーション。

### 日本語フォントの共通適用版の公開（2026-10-26）

ゲーム本文で使っていたNoto Sans JPをWebのプロジェクト共通テーマへ設定し、標準ラベル・ボタン・ツールチップにも適用。文字の太さは600を維持する。Webページの全画面ボタンと起動エラー表示には、同梱TTFから生成したWOFF2を自サイトから配信する。

Workerバージョンは `22b8ac3f-1697-4344-97e4-880a16fc4839`。Godot41項目とローカルWeb10項目を並列検証し、公開先でもPC・タッチのフォント配信／適用6項目が成功。証跡は `build/japanese-font-final`、`build/japanese-font-web-final`、`build/japanese-font-responsive-final`、`build/japanese-font-production`。HTML / PCK / WOFF2のハッシュ一致は `build/japanese-font-deployment.json` に記録した。

### 目的地の分散配置版の公開（2026-10-26）

目的地を左右と奥行きに分散し、互いに最低90m離す。各入口へ通じる道路とミニマップの範囲も更新する。生成バージョンを保存し、既存の走行中マップはそのまま保持する。新しいラン／次のコースから適用。

Workerバージョンは `8ad35cb8-2da0-41d1-8260-8e20bbf2b729`。Godot594項目、ローカルWebのPC29項目・タッチ18項目を並列実行し、すべて成功。256パターンの間隔・道路と柵／地雷の非交差・実走行での到達・保存復帰・5戦の連続プレイを確認した。証跡は `build/destination-spacing`、`build/destination-travel`、`build/destination-web-desktop`、`build/destination-web-touch`。公開HTML / PCKとビルドのハッシュ一致は `build/destination-deployment.json` に記録する。

### フッター共通化・レスポンシブ版の公開（2026-10-26）

PCとタッチで同じカテゴリ・設備・操作アイコンを使い、狭い画面では構築時3段／戦場1段へ配置する。収納・装甲開閉も共通アイコンから操作でき、移動パッドはフッターより上に収める。出撃時は収納モードと案内を解除する。

Workerバージョンは `d25b8283-d064-4699-a411-ad8e3b1e14d1`。関連Godotテスト233項目とローカルWeb51項目が成功。出撃時表示の追加修正後、Godot125項目（追加1項目を含む）と公開URLのタッチ18項目・レスポンシブ4項目を再検証した。独立テストを並列実行。HTML / PCKの一致は `build/footer-deployment.json`、証跡は `build/footer-final`、`build/footer-departure`、`build/footer-production-touch`、`build/footer-production-responsive`。スマホはChromiumエミュレーションで、Android / iPhone実機は未検証。

### メニュー共通化・レスポンシブ版の公開（2026-10-26）

一時停止・設定・履歴と倉庫を元の表示へ統一。Godotの `ScrollContainer` で画面幅に合わせて拡縮し、高さが足りない場合はスクロールする。タイトルは縦横比に応じて戦車と左メニューを配置し、縦画面のHTMLブロックを廃止した。

Workerバージョンは `080ba43b-016a-4ddd-9ff7-7ee155281b9f`。Godot 235項目とWeb 51項目が成功し、公開先でもマウス・タッチの縦画面設定操作とリサイズを確認。HTML / PCKのハッシュ一致を `build/responsive-deployment.json` に記録した。証跡は `build/responsive-final`、`build/responsive-web-desktop`、`build/responsive-web-touch`、`build/responsive-production`。

### タッチ対応版の公開（2026-10-26）

Godot標準入力によるスマホ操作と専用スタート画面を公開。Workerバージョンは `d9650e4c-9f7f-4daf-bc22-2951934de076`。公開HTMLとPCKのSHA-256が検証済みビルドと一致することを確認した。

Godotの関連回帰147項目、公開URLでのPCブラウザ29項目・スマホ相当Chromiumタッチ検証18項目が成功。証跡は `build/touch-final`、`build/web-production-verified`、`build/web-touch-production`、`build/mobile-deployment.json`。Android / iPhone実機とSafariは未検証。

### 装備方式更新後のローカル検証（2026-10-23）

ミニマップの寿命修正を含む `2bfa9f6` のローカルWeb出力は29項目成功。個体ID・品質・設置位置を含む保存復帰と、品質順表示での一括解体を実クリックで検証しました。対象のノーマル2個だけからスクラップ9・石炭5を得てアンコモンを保持し、キャンセル時の無変更と再読込後の二重獲得防止を確認しています。最新の証跡は `build/equipment-audit/minimap-web`。この結果は公開先へのデプロイを意味しません。
