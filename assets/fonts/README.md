# Noto Sans JP

Web版はOSの日本語フォントを参照できないため、このフォントを同梱する。
NotoSansJP.ttfはGoogle Fontsの公式リポジトリから取得した未改変の可変フォント。

- 配布元: https://github.com/google/fonts/tree/main/ofl/notosansjp
- ライセンス: SIL Open Font License 1.1（同梱のOFL.txt）
- 取得日: 2026-10-22
- ゲーム内のWeb表示ではweight 600を使用する。

Webのプロジェクト共通テーマは `web_theme.tres`。通常のボタン、ラベル、ツールチップも同じ日本語フォントを使う。Godotの `gui/theme/custom.web` でWeb版に適用する。日本語フォントはMSDF（生成サイズ96）で描画し、スマホ用メニューの拡大・縮小でも文字の輪郭を維持する。ネイティブ版のシステムフォントも同じ描画方式を使う。詳しくは[Godot公式のフォント描画説明](https://docs.godotengine.org/en/stable/tutorials/ui/gui_using_fonts.html#multichannel-signed-distance-field-msdf-font-rendering)を参照。

Webページの全画面ボタン・起動エラー表示には `web/fonts/NotoSansJP.woff2` を同じ配信元から読み込む。既存TTFをWOFF2へ変換したもので、文字の削減は行わない。配信時には `NotoSansJP-LICENSE.txt` を同梱する。

WOFF2の再生成（作業用依存は配信対象外）:

```sh
python3 -m pip install --target build/font-tools 'fonttools[woff]==4.60.1'
PYTHONPATH=build/font-tools python3 - <<'PYFONT'
from fontTools.ttLib import TTFont
font = TTFont('assets/fonts/NotoSansJP.ttf')
font.flavor = 'woff2'
font.save('web/fonts/NotoSansJP.woff2')
PYFONT
```

Godot公式資料: [プロジェクト共通テーマ](https://docs.godotengine.org/en/stable/classes/class_theme.html)、[プラットフォーム別設定](https://docs.godotengine.org/en/stable/tutorials/export/feature_tags.html)。

スマホではCSS上の表示サイズと端末の描画ピクセル密度を分けて扱う。3倍密度でもボタン・文字の表示サイズは維持し、キャンバスと3Dプレビューは実ピクセル数に合わせて描画する。Webキャンバスの最大幅・高さを画面内に制限し、画面回転時に古い横幅でブラウザーがページ全体を縮小することを防ぐ。
