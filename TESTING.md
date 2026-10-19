# 検証手順

Godot 4.7.2 / Compatibility / macOSで確認。実行場所はプロジェクト直下。
Godot実行ファイルを指定し、下記のスクリプトを実行する。

```sh
/Users/dice/Downloads/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tests/factory_test.gd
/Users/dice/Downloads/Godot.app/Contents/MacOS/Godot --path . --script res://tests/variety_test.gd
```

画面描画が必要な試験には `--headless` を付けない。描画完了を待つ処理があるため、画面なしでは終了しない。画面試験は1つずつ実行する。

| スクリプト | 項目数 | 画面描画 | 主な検証 |
|---|---:|---|---|
| factory_test.gd | 33 | 不要 | 生産・搬送・合流・分岐・保存・燃料 |
| tank_ui_test.gd | 37 | 必要 | 3D車体・砲塔・可視物資・実入力 |
| battle_test.gd | 32 | 必要 | 自動走行・射撃・燃料停止・視点切替・走行中編集 |
| run_test.gd | 40 | 不要 | 5戦・資源・持越・報酬・ルート・ボス・撤退 |
| run_ui_test.gd | 9 | 必要 | 報酬・ルート・出発・メニュー撤退・選択時の表示領域 |
| checkpoint_test.gd | 23 | 不要 | 生産・敵・飛翔弾の復元、同一進行、破損・バックアップ |
| menu_test.gd | 21 | 必要 | 開始・続きから・保存・新ラン・配置管理・カメラ・装甲・撤退・入力遮断 |
| history_test.gd | 12 | 必要 | 結果・64bitシード・重複抑止・履歴上限・復旧 |
| blueprint_test.gd | 29 | 必要 | 開放・旧プロフィール移行・永続化・実クリック・実生産・予備弾16発 |
| variety_test.gd | 30 | 必要 | 32シード再現・実速度と燃料・編成・装填と積載・新旧保存 |
| campaign_variety_test.gd | 28 × 2 | 不要 | 6シード×2構成×安全／危険ルートの24ラン |
| supply_recovery_test.gd | 15 | 不要 | 走行中の供給再接続・枯渇時撤退・再出撃 |
| logistics_test.gd | 31 | 必要 | 診断・実回収・積み残し・停止／再開・屋根・入力透過 |
| audio_test.gd | 31 | 必要 | 実波形・音量・停止・設定保存・破損・8音上限・バス解放 |
| window_test.gd | 58 | 必要 | 5サイズ・実クリック・最小サイズ・表示専用ヘッダー・フッター操作・中央画面 |
| soak_test.gd | 11 | 不要 | 加速4時間・60回の再出撃／復帰・ノード／オブジェクト上限 |
| pack_smoke_test.gd | 9 | 書き出し後 | 空フォルダからのPCK起動・資源同梱・生産／戦闘 |

ソース上の試験440項目（通しプレイを安全／危険の2設定で実行すると468項目）、書き出し後のPCK試験9項目。各スクリプト末尾のRESULTが0 failuresであること、終了コードが0であること、SCRIPT ERROR / ERRORがないことを確認する。
試験用プロフィールはtests/profile_fixture.gdでプレイヤーの保存先と分離し、終了時に除去する。中断保存の試験も専用の一時保存先を使う。

## 実終了と再開

次を順に別プロセスで実行する。前半は実際にウィンドウ終了通知を受けて保存・終了し、後半は保存を読み取って進行を検証する。

```sh
/Users/dice/Downloads/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tests/exit_save_test.gd
/Users/dice/Downloads/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tests/exit_save_test.gd -- --verify
```

EXIT SAVE RESULT: PASSを確認する。エディター側の読込は次で確認する。

```sh
/Users/dice/Downloads/Godot.app/Contents/MacOS/Godot --headless --path . --editor --quit
```

## 画面確認

画面試験はpreview-*.pngを生成する。設置物・資源・加工品の判別、砲塔の透明度、向きと射撃、アイコン・数値・カードの重なりを目視確認する。
直近の追加画面はpreview-expanded-reward.png（装填・積載報酬）とpreview-expanded-routes.png（地形・編成・速度・燃料の比較）。

## 通しプレイの範囲と残る検証

campaign_variety_testは並列／備蓄の2構成から開始し、第2戦前に燃料を並列化、備蓄型は第3戦前に弾薬を増設する。安全寄りのルートと加工・燃費重視の報酬選択を使う。
6シード×2構成を安全／危険の2方針で実行し、24ラン全5戦の勝利を確認。危険方針は敵総耐久＋地形燃料倍率×10が高い候補を選ぶ。全3地形・全3編成を実際に通ったことも検証する。危険方針の並列型は残耐久86〜100、備蓄型は44〜80。安全方針より被害が増えるが、有限原料で完走できた。これは全シード・全報酬順・全ルートの勝利保証ではない。

追加設定は次で実行する。

~~~sh
/Users/dice/Downloads/Godot.app/Contents/MacOS/Godot --headless --path . --script tests/campaign_variety_test.gd -- --dangerous
/Users/dice/Downloads/Godot.app/Contents/MacOS/Godot --headless --path . --script tests/supply_recovery_test.gd
~~~

supply_recovery_testは実ゲームの燃料／弾薬の接続を開始後に切り、12秒後に走行中編集でつなぎ直す。無料の物資追加なく走行と射撃が再開すること、原料ゼロでも撤退・新ランに進めることを15項目で検証。長時間と画面サイズは下記の専用試験で確認済み。配布アプリと最終監査はROADMAP.mdで追跡する。

物流表示の試験はpreview-logistics.pngとpreview-pickup.pngを出力する。新規31項目と、変更に関連する既存138項目（工場・戦闘・保存・ラン・メニュー）を確認した。

## 音声の確認

Godot --audio-driver Dummy --path . --script res://tests/audio_test.gd

画面なしでは再生を無効にするため、音声試験にはheadlessを付けません。Dummyドライバーで実機から音を鳴らさず、AudioEffectCaptureからミキサーの波形を取得します。8音重なり時の出力が0より大きく1未満であること、停止後に無音になること、終了時に専用バスが残らないことを検証。音量のクリック試験でpreview-audio-menu.pngを生成します。

exit_save_test.gdもheadlessなし・Dummyドライバーで実行してから、--verifyで保存を検証すると、音声再生中からの実終了を確認できます。通常ゲーム試験はプロフィール用ヘルパーで音を無効化し、ユーザーの音量設定と試験用設定を分離します。新規31項目と既存64項目、画面あり／なしの終了を確認済み。

## ウィンドウ・加速長期動作・配布データ

window_testは最小960×628から1920×1080まで5サイズを、実ウィンドウの寸法と入力変換を含めて確認する。preview-window-*.pngで目視確認。理想の一様縮尺に対する誤差が各軸1物理ピクセル以内であることを検証する。
右側パネルをなくした配置では、ヘッダークリックが操作しないこと、フッター内のボタンに重なりがないこと、メニュー操作と5サイズの配置クリックも検証する。preview-layout-interior-*.pngで中央画面と操作領域を目視確認できる。

Escメニューの1列化では、実際のボタン位置からクリック座標を取り、メニュー21項目・設計図29項目・音声31項目・5サイズのウィンドウ58項目を確認した。preview-menu.pngとpreview-window-960-628.pngで、アイコン＋文字、4pxの内側余白、最小画面に全項目が収まることを目視確認できる。

soak_testは工場のみを加速4時間、ゲームを60回の撤退／再出撃／中断復帰に通す。最初の設備生成・プール確保後に基準を取り、初期と終盤のノード・オブジェクト・リソース数を比較する。無制限原料は工場単体の定常動作試験にだけ使用し、ラン通し試験は有限原料を維持する。

pack_smoke_testをソースプロジェクトの作業フォルダから直接実行してはいけない。Godotは同名の生ファイルを参照できるため、独立性の証拠にならない。tools/export_pack.pyはPCKを生成し、一時的な空フォルダに試験用スクリプトだけをコピーして実行する。除外ファイル・動的読込の音声・起動・生産・有限原料・走行・射撃・メニュー停止の9項目を検証し、manifestを出力する。

クリーンソースの確認はgit archive HEADを新しい一時フォルダへ展開し、そのフォルダでGodotの--editor --quit、--quit-after 5、factory_test.gdを順に実行する。2026-10-08に初回インポート・起動・工場33項目がすべて成功。既存.godotキャッシュをコピーしないこと。


## macOSリリースアプリ

tools/export_macos.pyは公式macOSリリーステンプレートで書き出し、ZIPを空の一時フォルダに展開して、アプリ自身の実行ファイルで画面なし5フレームと画面あり10フレームの起動・終了を検証する。Apple Silicon/Intelの両アーキテクチャをlipoで確認。外部Godotやソースプロジェクトのパスを起動引数に渡さない。

リリーステンプレートにはエディター用の--script引数がないため、外部のpack_smoke_testをリリース実行ファイルへ渡しても検証にはならない。独立起動2項目と、ソース／PCKのゲーム機能試験は区別する。書き出したアプリ上での実操作は下記のとおり確認。全要件の最終監査はAUDIT.mdに記録済み。

2026-10-08：ソース全16スイート410項目と、実終了・別プロセスの保存読込が成功。build/auditに各実行ログを保存。macOS書き出しではApple Siliconに必要なimport_etc2_astc設定の不足を修正した。

単体アプリ実操作（2fc352d / ZIP SHA-256 99da4e5b0c444501b9c47b08b31bcff8ebe1f5afeb5ab59f490f12f58fac189d）：プロジェクト外へ展開し、開始・自動戦闘・走行中編集・B/Tab/Space・初戦クリア・報酬選択・次ルート選択・保存終了を実クリックで操作。再起動後に続きからを選び、製造数46、ライン上の物資、燃料、配置を保った第2戦準備へ停止状態で復帰することを画面確認した。テストスクリプトを単体アプリへ注入していない。
