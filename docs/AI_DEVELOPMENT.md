# AI開発フローと引き継ぎ知識

更新日: 2026-10-30。プロジェクト直下の [AGENTS.md](../AGENTS.md) が短い入口。本書は作業手順と判断の根拠をまとめる。数値や分類が変わったときはコード・テストを確認して更新する。

## 1. 着手から完了まで

1. `git status --short`、`git branch --show-current`、`git log -3 --oneline` で作業状態を把握する。前の作業の未コミット差分を今回の変更で上書きしない。
2. ユーザーの最新指示と、継続中の依頼を合わせて対象を決める。曖昧でも独立して進められる調査・実装は進める。
3. `rg` / `rg --files` で状態の所有者、UI、保存、生成元、既存テストを探す。UI上の症状でも、状態管理・座標変換・実行フェーズを先に調べる。
4. 関連する最小の変更を行い、必要な仕様資料と既存の回帰試験を更新する。単純な表示変更のためだけに実装をなぞるテストを増やさない。
5. ソース編集を止め、対象スイートをヘッドレス・最大4並列で実行する。失敗時はログを見て、製品の不具合か古いテスト前提かを切り分ける。
6. 公開が依頼されている場合は、最新ソースの書き出し、必要なWeb確認、デプロイ、公開ファイルの照合まで行う。pushの依頼には差分確認・commit・push・同期確認まで含める。
7. 最終報告は変更結果、実施した検証、未実施の公開作業や実質的な制約を簡潔に伝える。実装完了・ビルド成功・公開完了を同じ意味で使わない。

権限エラーが起きた場合は環境の正規の承認機構を使う。既存の承認を繰り返し求めたり、認証・sandboxを迂回したりしない。共有リポジトリのforce pushや、プレイヤーの保存データ削除は通常の修正手順に含めない。

## 2. 環境と起動

| 項目 | この環境での設定 |
|---|---|
| 作業ディレクトリ | `/Users/dice/Proj/last-supply-line` |
| Godot | 4.7.2、Compatibility renderer |
| Godot実行ファイル | `/Applications/Godot.app/Contents/MacOS/Godot` |
| Python | 3.9以降。ランナーは標準ライブラリで動く |
| Node | `package.json` は22.18以上を要求。この環境では22.23.0を使用 |
| Nodeの実体ディレクトリ | `/Users/dice/.local/share/mise/installs/node/22.23.0/bin` |
| 開始シーン | `scenes/start_screen.tscn`。ゲーム本体は `main.tscn` |
| Git | `origin` は `git@github.com:dicenull/last-supply-line.git`、使用中のブランチは `main` |

機器依存のパスは別環境で読み替える。Nodeの選択が必要なら、コマンドの環境にだけPATHを付ける。

```sh
env PATH="/Users/dice/.local/share/mise/installs/node/22.23.0/bin:$PATH" node --version
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --editor --import --quit
```

初回インポートは通常 `tools/run_tests.py` が行うため、毎回別途実施する必要はない。テストランナーと書き出し処理を、同じ `.godot` キャッシュへ同時に実行しない。

ユーザーがゲーム起動を依頼した場合のコマンドは [BUILDING.md](BUILDING.md) を参照する。テストのためにGUI起動を流用しない。

## 3. 責務と変更箇所の見つけ方

| 変更対象 | 主なファイル | 注意点 |
|---|---|---|
| ゲーム全体の接続・入力・フェーズ遷移 | `scripts/factory_view.gd` | 状態クラスや専用UIを接続する場所。新しい数値ルールを一極集中させない |
| 生産、配置、弾薬、資源、破壊・修復 | `factory.gd` / `factory_layout.gd` | 固定ポートと通常設備を区別。初期資材ブロックと防御ブロックは通常設備 |
| ラン、報酬候補、ショップ、結果 | `run_state.gd` / `run_results.gd` | 面の集計を一度だけ行う。報酬の表示と実取得の品質を一致させる |
| キル・コンボ、勝敗・HP、移動 | `battle_score.gd` / `battle_progress.gd` / `battle_motion.gd` | HUDから再計算・再加算しない。移動の適用結果と入力要求を区別 |
| 戦場、敵、弾、現地ドロップ | `battle_world.gd` | 生死の入口で二重撃破を防止。素材は現地で回収して初めて所持量へ加算 |
| 道路・目的地・障害物 | `map_shapes.gd` / `field_course.gd` / `course_obstacles.gd` / `destination_defenses.gd` | シードと生成版を保持。既存セーブの地形を差し替えない |
| 装備の取得・換装・配置・収納 | `equipment_inventory.gd` | UIの選択、ドラッグ、設置済み状態を混同しない。保管弾も維持 |
| 装備定義、発動条件、性能 | `equipment_catalog.gd` / `equipment_activation.gd` / `vehicle_parameters.gd` | 設置できることと効果が有効なことを区別する |
| 共有3Dモデルと武器の段組み | `item_model.gd` / `item_model_preview.gd` / `weapon_mount_layout.gd` | 地面・一覧・車体で同じ型式を使う。原点・旋回・砲身・給弾口を確認 |
| 車内・装備の3D表示 | `tank_world.gd` | モデルの拡大だけで当たり判定や設置可否を変更しない |
| Q/Eペインとアイコン列 | `equipment_workspace.gd` / `equipment_loadout_panel.gd` / `equipment_inventory_panel.gd` / `gameplay_footer.gd` | 下中央の建設ドック・右端の操作列と干渉させず、スクロール不要の一覧を保つ |
| タッチ入力・浮動操作 | `touch_controls.gd` / `field_actions.gd` | 実タッチとエミュレートされたマウスを二重処理しない |
| 取得通知・コンボHUD | `equipment_loot_feed.gd` / `logistics_overlay.gd` | 通知は所持品を変更しない。表示中の同種素材は合算する |
| 航空支援・選択・結果画面 | `supply_airdrop.gd` / `run_choice_popup.gd` / `result_page.gd` | 演出は報酬を直接与えない。スキップ・保存復帰でも重複させない |
| 保存と復元 | `run_save.gd` / `run_snapshot_schema.gd` | 読込前に検証し、不正な状態で現在のゲームを破壊しない |
| 音声 | `game_audio.gd` / `audio_observation.gd` | 有限の音声プール、音量設定、停止・再開・ロードの一時状態を守る |

表の省略パスはすべて `scripts/` 配下。

### 生成ファイル

装備の現行定義は40種（設置装備16種・車体パーツ24種、うち史実パーツ12種）。旧型式のIDは保存互換のために残す。旧資料の「300型式」はそのまま現行の抽選対象数を意味しない。

`data/equipment_current.json`、`data/equipment_identity.json`、`data/vehicle_parts.json`、`data/historical_parts.json` 等の生成元を変更し、次を実行する。生成物だけを手修正しない。

```sh
python3 tools/generate_equipment.py
python3 tools/generate_equipment.py --check
```

機械音・取得音・飛行音の生成は `tools/generate_feedback_audio.py`。モデルはコードで組み立てている。新規スクリプトの `.uid` と、必要な音源・フォント等のインポート設定を落とさない。

## 4. 維持すべきゲーム仕様

- **修復はラインだけで、HPはそのまま。** クリア後の無料修復でも回復させない。HPのみ減少している場合はライン修復の対象外。
- ビルドの強さは、パイプ接続・設置位置・弾薬消費・燃料・移動性能などの組み合わせと代償から生まれる。特定セット名の成立だけで付くボーナスには戻さない。
- 装甲は外周、駆動系はエンジン隣接、弾薬加工系は実際の給弾経路への接続が必要。無効配置を許可する場合も、表示と実効果・消費を一致させる。
- 初期のギア・エンジン・履帯・主砲は装備中の所持品として一覧にある。外す操作、装備なしの見た目、基礎性能との重複加算防止を維持する。
- 副砲の設置範囲は重なりを許し、二段配置にする。給弾口のアンカーと装填弾は独立。主砲は2×2給弾口ごと移動する。
- 武器の二段化は2段への割り当てであり、任意の多数密集配置で全メッシュが完全非干渉になる保証ではない。形状変更時は実メッシュを確認する。
- レア度の識別色はモデルの一部、地面のリングや目印に使う。型式・品質の形状差を保ち、全面を鮮やかに塗り替えない。
- 連続撃破は2.8秒以内。通常敵の廃材・石炭に `+0, +1, +1, +2, +2, +3…` を加える。コンボ終了・ロードで現在のボーナスをリセットするが、既存ドロップの量は維持する。
- クリア報酬の補給箱は各候補90%レア・10%レジェンダリー。ラン・面・候補から決める別の決定的乱数を使い、表示・保存復帰・選択で再抽選しない。
- 航空支援中は報酬・リザルトを隠す。メニュー中は演出を停止。着地後は投下画面上のモデルを選んで詳細を表示し、「獲得」で1つ取得する。別の3択カード画面は開かない。途中保存の復帰は同じ投下画面の選択状態へ戻し、飛来や取得通知を再生し直さない。
- 最終面は大型基地1つと入口前のボス。クリア後は支援演出からリザルトへ進む。

## 5. ヘッドレス・並列テスト

### 実行と判定

```sh
python3 tools/run_tests.py --headless-only --jobs 4 --list
python3 tools/run_tests.py --headless-only --jobs 4 --timeout 90 \
  --suite responsive_footer --suite touch_controls --suite field_services \
  --suite footer_tools --suite loadout_ui --suite equipment_ui \
  --output build/ui-headless
```

`--headless-only` は `VISUAL` の試験を自動変換するオプションではない。指定すると未対応試験を拒否する。引数なしのランナーはGUIも起動するため使わない。現在はフッター、倉庫、装備UIなどもヘッドレスで操作・配置を検証できる。

| 変更分野 | 関連するヘッドレス試験の例 |
|---|---|
| フッター・ペイン・タッチ | `responsive_footer`, `footer_tools`, `touch_controls`, `loadout_ui`, `equipment_ui`, `field_services` |
| 装備と位置制約 | `equipment_activation`, `emergent_builds`, `weapon_mounting`, `vehicle_parameters`, `equipment_inventory`, `equipment_save` |
| ドロップ・コンボ・通知 | `battle_state`, `combo_loot`, `ground_items`, `equipment_feedback`, `arsenal_feedback` |
| マップ・基地 | `map_shapes`, `destination_spacing`, `destination_defenses`, `course_goal`, `final_base` |
| 保存・初期配置 | `checkpoint`, `equipment_save`, `starting_resources`, `starting_armor`, `factory_layout` |

この表は実行候補であり、毎回全部を実行する指示ではない。最新の分類はランナーを見る。`supply_airdrop`、`result_ui`、`item_catalog_page` はヘッドレス対応済み。`audio` などはまだ `VISUAL` にある。ヘッドレス化をせずに起動しない。

結果は出力先の `summary.json`、`import.log`、各スイートのログ、`source-hashes.json` を読む。終了コード0、全対象の成功、`changed_sources: []` を確認する。PASS行の途中経過だけで完了扱いしない。過去の失敗ログを消して見かけ上成功にせず、修正後の出力先を分ける。

### テスト作成・改修の注意

- `tests/profile_fixture.gd` の `Fixture.assign(game, suite_name, 2)` を使う。既定のレイアウト版1は旧配置試験用。現在の車体を試すなら2を明示する。
- Fixtureが隔離するのはプロフィール・音量設定・配置保存。中断保存のファイルパスは自動隔離されない。書き込みには `build/<suite>/…` 等の専用パスを指定する。
- プレイヤーの `user://run_save.mfv` や通常プロフィールをテストで上書きしない。ブラウザーも専用context・専用IndexedDBを使う。
- 終了時にノード・Fixtureを解放する。新しいテストは `tools/run_tests.py` の分類に追加する。`crafting` は既存試験への別名で重複集計しない。
- ランナー実行中は `.gd` / `.tscn` / `project.godot` を編集しない。テストと書き出しの同時インポートも避ける。
- ヘッドレスでは `RenderingServer.frame_post_draw` を待ち続けない。`get_texture().get_image()` や画像保存をガードする。必要な `process_frame` 待ちは残し、UIの配置更新まで飛ばさない。
- 描画部分を省いても、実入力・状態遷移・矩形の収まり・重複取得の検査は残す。GPU描画や実ミキサー出力を検証したと報告しない。
- 長時間試験では実時間と加速したゲーム内時間を区別する。古い固定操縦の完走率を、人間の勝率や最新のHP仕様の正しさと同一視しない。

### UIで実際に起きた問題

1. **論理座標と画面座標。** `root.push_input(event, false)` へ渡すマウス位置は `root.get_final_transform() * 論理座標`。一方、ゲームの `cell_at()` を直接呼ぶときに二重変換しない。レターボックスの平行移動も含める。
2. **小画面の最小サイズ。** `factory_view._ready()` がWindowの最小サイズを設定する。小画面テストではシーンを追加した後に `root.min_size`、`root.size` を設定し、フレームを待つ。
3. **矩形の浮動小数誤差。** 境界一致は `is_equal_approx` や小さい許容差で比較する。見た目のはみ出しを大きな許容差で隠さない。
4. **ペインがクリックを遮る。** フッターを小さくすると車内領域とペインも変わる。以前クリックできたマスがパラメータペインの下に隠れることがある。テストは対象を露出させてからクリックする。製品側でGUI入力を貫通させて直さない。
5. **浮動ボタンの描画順。** 3Dビュー内部に置くボタンを親Controlの `_draw()` で描くと、後から描かれるSubViewportに隠れる。建設・操作アイコンと出撃FABはCanvasLayer 4上のButton自身で描画する。選択肢6・倉庫8・結果9・メニュー10より下に置き、モーダルを貫通して操作できないようにする。
6. **浮動ボタンの位置。** 画面下の帯は撤去済み。ワールドは下端まで表示し、倉庫・性能ペインは `workspace_rect()` で建設ドック・右端の操作列を避ける。`footer_rect()` は互換名で建設ドックだけを返し、戦場では高さ0。修復は出撃FABの上に配置し、右列と重なる場合は横へ逃がす。
7. **クリア・大破の演出。** クリア直後に結果画面が見えるという古いassertは、演出開始→演出終了→選択／結果を検証する形へ変える。HP0では車体の連続爆発後に共通リザルトを表示する。ロード後に飛来や爆発を再開させることでテストを通さない。
8. **Web保存の待ち方。** ヘッドレスWebGLでは描画とIndexedDB同期の完了がずれる。固定の1〜2秒待ちで保存を読むと、操作前のファイルを検証してしまう。`web_loadout_test.cjs` は保存操作より新しいファイル時刻を確認してから復号する。状態待ちは `polling: 250` と期限を設け、バックグラウンドの描画フレームだけに依存させない。
8. **JSONの版番号。** GodotのJSON値はfloatになる場合がある。整数配列の `Array.has()` だけで版判定すると旧配置を拒否したことがある。型と比較を確認する。

## 6. Web書き出しとブラウザーテスト

```sh
python3 tools/export_web.py --godot /Applications/Godot.app/Contents/MacOS/Godot
npm run dev:web
```

Godotと同じ版の `web_nothreads_release.zip` が必要。初回は `--template /path/to/web_nothreads_release.zip` を指定する。保存先は `build/web-templates/`。WebはCompatibility・シングルスレッド。

`npm run dev:web` は起動したまま、別の実行でブラウザーテストを行う。標準URLは `http://127.0.0.1:8791`。既存サーバーがある場合はそのプロセスと配信対象を確認し、ユーザーのプロセスを終了して置き換えない。

- 出力は `build/web/`、配布ZIPは `build/MFV03-web.zip`、照合用manifestは `build/mfv03-web-manifest.json`。
- `/index.wasm` はWorkerが `index.wasm.gz` を `Content-Encoding: gzip` 付きで返す。単純な `python -m http.server` やHTMLの直接起動を代わりに使わない。
- 日本語は見出しにDela Gothic One、UIにBIZ UDPGothic Regular/Bold。PC・Web共通テーマと同梱WOFF2を使う。MSDF、CSSピクセル、DPRを区別する。取得元・ライセンス・再生成は `assets/fonts/README.md`。
- `tests/web_*_test.cjs` のChromium起動は `headless:true` にしてある。GPU描画のスクリーンショット取得もウィンドウを開かず行う。

```sh
WEB_URL=http://127.0.0.1:8791 WEB_AUDIT_DIR=build/web-map-check \
  node tests/web_map_shapes_test.cjs
TOUCH=1 DPR=3 WEB_URL=http://127.0.0.1:8791 WEB_AUDIT_DIR=build/web-loadout-touch \
  node tests/web_loadout_test.cjs
```

`web_map_shapes_test.cjs` は内部でPCとスマホを並列実行する。異なるテストを並列に走らせる場合も、出力先とブラウザーcontextを分離する。Nodeが古ければ前述のPATHを付ける。Chromium未導入時だけ `npx playwright install chromium` を使う。

### ブラウザーテストの前提成果物

| 成果物 | 生成元・用途 |
|---|---|
| `build/loadout-ui/geometry.json` | `loadout_ui`。フッター、ペイン、準備／戦闘の実ボタン座標 |
| `build/equipment-audit/placement-geometry.json` | `equipment_ui`。車内の配置対象座標 |
| `build/catalog-ui/title-geometry.json` | `item_catalog_page`。タイトル操作の座標 |
| `build/loadout-ui/web-fixture.mfv` | `loadout_ui`。換装用の保存Fixture |
| `build/result-ui/web-fixture.mfv` / `geometry.json` | `result_ui`。結果画面の保存Fixtureと座標 |

`build/` はGit管理外なので、新しいcheckoutにはこれらがない。UI変更後に古い座標を使わない。`item_catalog_page` と `result_ui` はヘッドレスでこれらの成果物を生成できる。**不足ファイルを埋めるために、GUI試験を無断で起動しない。**

ブラウザー内の保存ファイルはIndexedDBから取り出し、`tests/web_save_probe.gd` をヘッドレスGodotで実行して検証する。テスト用に製品へゲーム状態を直接変更するブリッジを追加しない。

## 7. 保存互換

本書更新時点のラン保存版は20、配置だけのJSONは3。旧ランは版1〜19を読める。版番号の正は `run_snapshot_schema.gd`。

状態変更時は、保存する値・復元時に再計算する値・一時状態を区別する。新規項目は検証、旧版の既定値、移行、破損拒否を合わせて確認する。先にスキーマを緩めて不整合を許容する修正はしない。

- キル数・最高コンボ・結果集計・所持品・未回収ドロップは引き継ぐ。現在のコンボ時間、押下状態、ドラッグ、通知、演出は引き継がない。
- 初期資材の撤去、移動した主砲、各砲の弾薬、装備なし、初期装備を保存して復元する。
- 同じ面の結果や同じ物資を二重加算しない。失敗したロードは現在のゲームを変えない。
- 主保存と `.bak`、チェックサム、上限と型検証を維持する。旧マップの生成方式と旧装備IDを保持する。

詳細は [SAVING.md](SAVING.md) と [BATTLE_STATE.md](BATTLE_STATE.md)。

## 8. Web公開とpush

公開先: `https://last-supply-line.dicenull-dev.workers.dev`。
`cloudflare.config.ts` がWorker名・バインディング、`wrangler.config.ts` が `build/web`・開発ポートを定義する。

1. ソース変更後にWebを書き出す。古い `build/web` が残っていても、そのまま配布しない。
2. 変更内容に必要なチェックを済ませる。配布設定変更時は `npm run check:deploy` も利用できる。
3. `npm run deploy:web` を実行し、終了コード、公開URL、Version IDを確認する。既存の認証を使い、毎回ログインし直さない。
4. 公開先のHTMLとPCKを取得し、manifestのサイズとSHA-256を両方比較する。取得にはキャッシュ回避用クエリを付ける。
5. 必要な公開スモーク試験は隔離したcontextで行い、`WEB_AUDIT_DIR` をローカル確認と分ける。最後にURLと検証結果を報告する。

公開確認の例。独立した2ファイルを並列取得し、不一致なら失敗させる。Pythonのurllibだけが403になりcurlでは取得できた事例があるため、ここではcurlを使用する。

```sh
python3 - <<'PY'
import concurrent.futures, hashlib, json, subprocess, time
from pathlib import Path

base = 'https://last-supply-line.dicenull-dev.workers.dev'
manifest = json.loads(Path('build/mfv03-web-manifest.json').read_text())

def verify(name):
    route = '/' if name == 'index.html' else '/' + name
    url = base + route + '?verify=' + str(time.time_ns())
    data = subprocess.check_output([
        'curl', '--fail', '--silent', '--show-error', '--location',
        '--max-time', '45', url,
    ])
    actual = {'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest()}
    assert actual == manifest['files'][name], (name, actual)
    return {'file': name, 'verified': True, **actual}

with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
    results = list(pool.map(verify, ['index.html', 'index.pck']))
Path('build/deploy-verification.json').write_text(json.dumps({
    'url': base, 'results': results,
}, indent=2) + '\n')
print(json.dumps(results))
PY
```

commit・pushの依頼時は `git diff --check`、対象差分、生成物・新規 `.uid` の不足を確認する。今回の依頼対象だけをstageし、`git diff --cached --check` 後にcommitする。既存ブランチへ通常のpushを行い、`git status --short` と `git rev-list --left-right --count HEAD...origin/main` で確認する。remoteやブランチが変わっていたら実際の追跡先を使う。

commitはWebの再書き出しでも再デプロイでもない。未コミット差分を含む公開ビルドもあるので、コミットIDだけで配信内容の一致を判断しない。ビルドmanifestには `source_commit` と `source_dirty` が記録される。

## 9. この引き継ぎ時点の状態

この節は2026-10-29時点の記録。次の作業では必ずGitと成果物を再確認する。

- 最後にpushしたコミットは `ea6b1c8`。航空支援、装備・マップ・UIの蓄積変更を含む。
- 最後に確認した公開Version IDは `d05f5a6a-1b10-4384-9468-00398ed0c5f6`。航空支援を含むHTML・PCKの一致、PC・スマホの公開テスト22項目を確認した。このブラウザーテストはヘッドレス運用への変更前の記録。
- その後のUI・フォント・ヘッドレス運用への変更は未コミット・未push・未デプロイ。ローカルWebを書き出して検証する。
- 最新指示でフッターを撤去。下中央の建設ドック・右端の操作列・右下の出撃FABへ変更。出撃はPCで直径96px、最小72 CSS px、見出し書体Dela Gothic One。その他の操作は44 CSS px以上。
- 最新UIのヘッドレス検証は `build/floating-dock-final/summary.json`。5スイート505項目、失敗0、ソース変更なし。見出し・カタログ・結果画面も `build/floating-dock-headless/` の関連ログで確認した。
- Webテストは `headless:true`。PC・スマホ1倍／3倍密度・画面回転・日本語フォントの27項目は `build/floating-dock-web-font-final/result.json` で確認済み。公開版の過去の成功を最新ローカル変更の検証結果として扱わない。
- 装備交換・収納・保存復帰・クリア画面のWeb確認24項目は `build/floating-dock-web-loadout-final/result.json`。再挑戦ボタンの補完後は `build/floating-dock-retry-final/summary.json` の3スイート197項目をヘッドレス並列で確認し、ローカルWebを書き出し直している。
- この文書だけの変更でゲーム回帰テストを再実行する必要はない。リンク、コマンド、試験名、実装と説明の整合を確認する。

一時的なプロセスID、認証情報、マシンの稼働状態は恒久的な手順に固定しない。`build/` の証跡はローカルにのみ存在し、別環境では再生成が必要。

2026-10-30追記: 外装は右列、回転・収納・削除の独立ボタンは撤去。一覧の明示的な閉鎖（×・E・I）はQも閉じる。配置開始時の自動hideは比較ペインを残すため、close_requestedと区別する。今回の最終検証は `build/right-rail-large-sortie-final/summary.json`（4スイート578項目、失敗0）。PC・スマホのヘッドレス画像は `build/right-rail-preview/`。一覧を閉じた画像が開く前の画像と完全一致することも確認した。

## 10. 自動変速と史実パーツ

- `battle_motion.transmission` が段数・正規化速度・進行方向を所有。加速と旋回を最大1/60秒刻みで積分し、実移動全体の軌跡を回収・地雷へ渡す。
- 停止、燃料切れ、完全な衝突停止で1速に戻す。後退は低速1段。停止入力と一時停止を区別し、メニュー中は加速状態を凍結する。
- 変速状態は版20の任意 `battle.transmission` として保存・検証する。旧保存に項目がなければ1速・停止状態。壊れた段数・比率・型式は読込前に拒否する。
- 新パーツを増やすときは [史実パーツと出典](HISTORICAL_PARTS.md)、生成元、取得時の品質、図鑑、装着時形状、主砲の発射位置まで整合させる。定義数を固定している旧テストも最新の仕様に合わせる。
- `transmission` / `historical_parts` を起点に、必要に応じ `tank_steering` / `collision_slide` / `checkpoint` / `vehicle_parts` を並列実行する。


## 11. 今回の検証証跡（2026-10-30）

史実12パーツ、自動変速、直接選択する航空支援、車体大破から共通リザルトへの遷移、モデル付きリザルトを追加。リザルトは設置物・車体装備を3Dモデルと名称で表示し、画面内のページ切替にする。

- 関連27スイート・4,707項目の最新結果は成功。並列実行は最大4、全てヘッドレス。個別の最終結果を `build/historical-web-preview/native-results.json` に集約した。
- `build/historical-final/`、`build/historical-ui-final/`、`build/historical-ui-verified/` にある失敗は旧テスト前提の修正前の記録。装備UIの最終成功は `build/historical-equipment-ui-final/summary.json`。過去の失敗ログは削除しない。
- `build/current-web-preview/` はPC・スマホでの航空支援の選択・取得、クリア／大破リザルト、透過ペインのヘッドレス画像。
- `build/historical-web-preview/` は史実パーツの図鑑・換装モデルのヘッドレス画像。Web書き出しはローカル更新であり、公開デプロイやpushの完了を意味しない。
