# Web版 / Cloudflare Workers

公開URL: https://last-supply-line.dicenull-dev.workers.dev

Godot 4.7.2のCompatibility / シングルスレッド版を、Cloudflare Workers Static Assetsで配信する。
WASMの圧縮済みレスポンスだけを小さなWorkerで返し、その他は静的配信する。サーバー側のゲーム処理、データベース、Pagesは使用しない。保存先は各ブラウザのIndexedDB。

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

PCのキーボードとマウスを使用する。ゲーム内操作はデスクトップ版と同じ。
音声は最初のクリック／キー操作後に有効になる。「終了」の代わりに「保存してタイトルへ」を表示する。
タブを閉じる前にEscメニューの「ランを保存」または「保存してタイトルへ」を使う。
ブラウザのデータ削除やプライベートモードでは保存が保持されない場合がある。
ブラウザや公開ドメインが異なるとセーブデータは共有されない。macOS版のセーブとは別。

## 公式資料

- [Godot: Exporting for the Web](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_web.html)
- [Godot: SystemFontの対応環境](https://docs.godotengine.org/en/stable/classes/class_systemfont.html)
- [Cloudflare: Static Assets](https://developers.cloudflare.com/workers/static-assets/)
- [Cloudflare: 配信ヘッダー](https://developers.cloudflare.com/workers/static-assets/headers/)
- [Cloudflare: Static Assetsの容量制限](https://developers.cloudflare.com/workers/platform/limits/#static-assets)

## 検証記録（2026-10-22）

ローカルと公開URLの両方で、Chromium 149の実描画19項目が成功。1440×940と960×628を目視確認。音声波形、実生産、W移動、IndexedDB保存、ページ再読込、停止状態での復帰、保存してタイトルへ戻る操作を確認した。デスクトップのメニュー回帰21項目も成功。Safari・Firefox・スマートフォンは今回の実機検証対象に含めない。

### 装備方式更新後のローカル検証（2026-10-23）

ミニマップの寿命修正を含む `2bfa9f6` のローカルWeb出力は29項目成功。個体ID・品質・設置位置を含む保存復帰と、品質順表示での一括解体を実クリックで検証しました。対象のノーマル2個だけからスクラップ9・石炭5を得てアンコモンを保持し、キャンセル時の無変更と再読込後の二重獲得防止を確認しています。最新の証跡は `build/equipment-audit/minimap-web`。この結果は公開先へのデプロイを意味しません。
