# 3D版 検証記録

環境：macOS / Apple M3 Pro / Godot 4.7.2 stable / Compatibilityレンダラー。

## 生産のルール

`tests/factory_test.gd`：26項目。

製造、実物資による給弾、並列化、物資保存、接続切断、方向、分配、合流の公平性、素材制約、容量、備蓄放出、集計窓、固定区画、配置制限、編集・停止・回転・履歴、JSON形式と不正保存の拒否を検証する。3D化にあたり生産ロジックは変更していない。

## 3D・入力

`tests/tank_ui_test.gd`：29項目。

- ネイティブの3Dカメラ・車体・屋根が生成される。
- 4つの床板で画面座標→床の逆変換が一致。
- 実際のマウス入力で設備配置、機械配置、回転、右クリック撤去、元に戻す。
- 屋根を閉じると配置不可。Tabで車内表示に戻る。
- カメラを回しても配置座標が正しい。
- マウスホイールで拡大、キーでも回転できる。
- 見本ラインを車内に作り、操作盤から運転開始。
- 製造・搬送・給弾・試射が進み、3D物資が生成される。
- 一時停止中の立体物資が動かない。
- ボタンに説明文がない。

3Dテストでは外観と稼働中のスクリーンショットを保存し、履帯・砲座・装甲・車内グリッドとUIを目視確認する。

```sh
godot --headless --path . --script res://tests/factory_test.gd
godot --path . --script res://tests/tank_ui_test.gd
```

UIテストは `preview-exterior.png` と `preview-tank.png` を上書きする。プレイヤーの保存ファイルは変更しない。

低性能GPU・他OS・ゲームパッド・タッチ操作は未検証。史実の戦車の寸法や兵器機構を検証するものではない。

## 全周砲塔・ピクセルアイコン追加検証

- 工場の生産を分離した空弾薬試験で、視覚上も発砲しない。
- 8発を与えると四方向へ2周、順番に試射する。
- 弾の進行方向が発射時の砲身方向と一致。
- 弾薬の消費数、シミュレーションの射撃数、表示の射撃数が一致。
- 発射光・砲身の反動・飛翔する弾が生成される。
- 23種類のアイコンが32×32で生成され、最近傍表示を使う。

Godot 4.7.2で追加後の26項目が成功。`preview-turret.png` は試験用に4発を用意して撮影した2方向目の発砲場面で、通常開始時の弾薬は0のまま。

中央前方・上部への砲塔移設と半透明化を3項目追加検証。拡大後も四方向の射撃・弾薬消費・反動を含む29項目がGodot 4.7.2で成功。実画面で下の床とラインが透けて見えることを確認。

## 自動対戦

`Godot --path . --script res://tests/battle_test.gd` で23項目を検証。対戦中の試射停止、配置保持、編集ブロック、製造弾薬との対応、画面往復と一時停止、見本ラインでの勝利、空ラインでの敗北、再戦を確認する。`preview-battle.png` を生成する。

燃料追加後：生産33項目、UI35項目、移動対戦23項目。石炭変換・燃料保存と消費上限・燃料切れでの射撃継続・走行距離との対応・段階出現・予告砲撃回避・クリックによって自動進軍が変化しないことを検証。

視点切替による再生状態の維持、車内視点での戦闘継続、走行中の配置・撤去、一時停止中の編集、再戦時の準備復帰を検証。

## Roguelike expedition

Run `Godot --headless --path . --script res://tests/run_test.gd` for 40 checks covering seeded choices, finite resources, upgrades, cargo/hull carry-over, a five-sector run with a second production line, final boss and retreat.
Run `Godot --path . --script res://tests/run_ui_test.gd` for 7 real-click checks of rewards, route selection, sector start and retreat; this captures preview-reward.png and preview-route.png.

## Checkpoint and menu

Run checkpoint_test.gd headless for 23 checks, and menu_test.gd with rendering for 10 real-input checks. Both use separate fixture save names and clean them up.
For exit verification run exit_save_test.gd once, then run it again with -- --verify; the second process validates and removes the saved fixture. This checks process exit and durable checkpoint creation.

## 出撃履歴

Godot --path . --script res://tests/history_test.gd

12項目。独立した試験用保存先を利用し、実撤退から履歴追加とメニュー描画まで確認します。

## 配置図アンロック

Godot --path . --script res://tests/blueprint_test.gd

29項目。画面描画を含むためheadlessは付けません。既存のbattle_test.gdも画面撮影を含みます。配置図の生産・備蓄・開放・永続化・UI選択・適用制約を確認します。tests/profile_fixture.gdでゲーム試験の履歴・アンロックをプレイヤーの保存先から隔離し、終了時に除去します。
