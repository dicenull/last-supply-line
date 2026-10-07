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
| run_ui_test.gd | 7 | 必要 | 報酬・ルート・出発・撤退の実クリック |
| checkpoint_test.gd | 23 | 不要 | 生産・敵・飛翔弾の復元、同一進行、破損・バックアップ |
| menu_test.gd | 10 | 必要 | 開始・続きから・保存・新ラン・Esc・入力遮断 |
| history_test.gd | 12 | 必要 | 結果・64bitシード・重複抑止・履歴上限・復旧 |
| blueprint_test.gd | 29 | 必要 | 開放・旧プロフィール移行・永続化・実クリック・実生産・予備弾16発 |
| variety_test.gd | 30 | 必要 | 32シード再現・実速度と燃料・編成・装填と積載・新旧保存 |
| campaign_variety_test.gd | 26 | 不要 | 6シード×2構成の12ラン、物資追加なしの全自動戦闘 |
| logistics_test.gd | 31 | 必要 | 診断・実回収・積み残し・停止／再開・屋根・入力透過 |
| audio_test.gd | 31 | 必要 | 実波形・音量・停止・設定保存・破損・8音上限・バス解放 |

合計341項目。各スクリプト末尾のRESULTが0 failuresであること、終了コードが0であること、SCRIPT ERROR / ERRORがないことを確認する。
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
6シード×2構成で全5戦の勝利を確認した。出力には勝敗・耐久・残資源・消費弾を残す。これは全ルートを勝てる保証や最終難易度の証拠ではない。

原料不足・燃料停止は個別試験を持つが、極端な構成、最悪ルート、長時間連続プレイ、複数解像度、配布ビルドは引き続きROADMAP.mdで追跡する。試験が通ったことだけでは完成判定しない。

物流表示の試験はpreview-logistics.pngとpreview-pickup.pngを出力する。新規31項目と、変更に関連する既存138項目（工場・戦闘・保存・ラン・メニュー）を確認した。

## 音声の確認

Godot --audio-driver Dummy --path . --script res://tests/audio_test.gd

画面なしでは再生を無効にするため、音声試験にはheadlessを付けません。Dummyドライバーで実機から音を鳴らさず、AudioEffectCaptureからミキサーの波形を取得します。8音重なり時の出力が0より大きく1未満であること、停止後に無音になること、終了時に専用バスが残らないことを検証。音量のクリック試験でpreview-audio-menu.pngを生成します。

exit_save_test.gdもheadlessなし・Dummyドライバーで実行してから、--verifyで保存を検証すると、音声再生中からの実終了を確認できます。通常ゲーム試験はプロフィール用ヘルパーで音を無効化し、ユーザーの音量設定と試験用設定を分離します。新規31項目と既存64項目、画面あり／なしの終了を確認済み。
