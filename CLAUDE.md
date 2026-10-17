# Maid Dragon Casino

ケモゲー1Week #1 のお題（スピード／仕事／がまん）を借りた自主制作ブラウザゲーム。
企画の詳細は `document.md`（ChatGPTとの企画相談ログ）を参照。

## 企画の要点
- 借金3000万を3日で返す、超高速マルチタスク・ギャンブルアクション（実力主体、運は従）
- A/S/Dキーで同時進行するミニゲーム（スロット＝タイミング、カード＝判断、ルーレット＝リスク）
- 欲張りゲージ・仕事追加・追加融資で自らリスクを上げる。ミスは即死ではなく収益減
- ナビゲーター：つるぷにメイドドラゴン（笑顔で無責任な助言）
- ビジュアル：地下カジノ×ネオン×90年代アーケード、派手だが判断対象の視認性は最優先
- 架空通貨のみ。全年齢向け。激しい点滅は控えめにし軽減設定を用意
- 方針：A（超高速・反射神経重視）を操作の基本とし、B（マルチタスク・リスク判断）の戦略要素を加える
- 画像の方向性：テスト画像 `assets/images/test_maid_dragon.png` の路線でOK
- 開発順：MVP（スロット＋カードを30秒同時処理）で面白さを検証してから拡張

## 現在の実装
- `scripts/game.gd`: 3日間のラン。TITLE（→ STORY あらすじ）→ DAY_INTRO → PLAYING(40秒) → SHOP(夜の闇市) → … → RESULT
  - タイトルは「スタート」「あらすじ」ボタン（キーは Space / A）。画面タップでは始まらない
  - 結果は3種のエンディング：大富豪（完済後さらに1000万以上）/ 完済 / 破産。絵は `assets/images/ending_*.jpg`
  - 暗幕（オーバーレイ）中は吹き出しが隠れるので、メイドのセリフは本文にも入れる
  - デバッグビルドのみ F1〜F3 で各エンディング、F4 で3日目の残り5秒、F5 で FEVER、F6 で指令（公開版は release なので無効）
  - 盛り上げ要素：コンボ15ごとに FEVER（6秒・収入x1.5）、メイドの無茶ぶり指令（6秒以内に n 回成功で +40万）、
    開店/閉店の演出、ラスト10秒は BGM が速くなり残り5秒はカウント音、所持金は数字が流れて増減する
- `scripts/scenario.gd`: セリフ集（メイド＝ボケ、ご主人様＝ツッコミ）。日ごとの会話・イベント・闇市の売り文句・エンディング
- `scripts/audio.gd`（Autoload `Audio`）: `Audio.bgm("play")` / `Audio.sfx("coin")` / `Audio.jingle("clear")`。M キーかタイトルの「音」でミュート
  - 1日目: スロット(A)、5秒後にカード(S)。2日目からルーレット(D)。借金3000万を3日目終了時に返せれば完済
  - 2・3日目はランダムイベント、夜は3つのアイテムから1つ選ぶ（メリット・デメリット付き）
  - 画面切替直後は連打で進まないよう入力ロック（通常1.2秒、ショップ2秒）。進行は Space / タップ
- `scripts/run_data.gd`: アイテム・イベントの定義。効果は `game.gd` の `_apply_mods()` で解釈
- `scripts/games/mini_game.gd`: ミニゲーム基底。`press()` で入力、`judged(text, amount, success)` で結果。
  `reward_mult` / `speed_mult` などの補正は毎日リセットして掛け直す
- `slot_game.gd`（7が枠に来たら押す。秒数で判定）/ `card_game.gd`（赤なら押す。早いほど高報酬）/
  `roulette_game.gd`（掛け金を払って針の位置の倍率で払い戻し。当たり枠は円の3割で、適当に押すと期待値マイナス。最大x4）
- 放置ペナルティ（`game.gd` の `NEGLECT_*`）: 1つのゲームだけに集中させないため、7秒触らないゲームは「放置中」になり
  2秒ごとに損失＋コンボ切れ。4秒で警告バッジを出す
- 数値（報酬・速度・判定幅）は各スクリプト先頭の定数で調整する
- タイトルに build（コミットSHA）を表示。CIが `version.txt` を書き出して同梱する。GitHub Pagesはキャッシュが最大10分残る

## 音
- BGM・効果音はすべて `tools/make_audio.py` で合成（外部素材なし）。曲を直したら実行し直して `godot --headless --import`
- BGM の `.wav.import` は `edit/loop_mode=2`（ループ）にしてある。WAV は取り込み時に QOA 圧縮される

## バランス確認
- `godot --headless --fixed-fps 60 -s res://tools/balance_sim.gd -- 30 detail`（数秒で終わる）
  - 腕前（上手い/ふつう）×遊び方（全部・1つだけ等）でボットに3日間遊ばせ、完済率と残額を出す
  - ボットは別のゲームに目を移すのに時間がかかる設定で、人間より少し上手い想定
- 目安（現状）：1つのゲームだけでは「上手い」でも完済0%、全部回せば「ふつう」で約8割完済
- 書き出しは GDScript の構文エラーがあっても成功してしまう。公開前にこの sim を1回流すと構文エラーに気付ける

## 技術スタック
- Godot 4.7.2（公式・非.NET版）、GDScript のみ（C#はWeb出力不可）、Compatibility レンダラー
- 1280x720、stretch=canvas_items
- 入力は `_input()` のイベントベースで処理し、演出（Tween等）で入力を止めない
- 操作は「レーン」で抽象化（`scripts/lanes.gd`, Autoload `Lanes`）。キー入力もタッチも `lane_N` アクションを発火する
  - ゲーム側は `Lanes.pressed_lane(event)` でレーン番号を得る。物理キー直書きはしない
  - レーン追加は `Lanes.LANES` に1行足すだけ（現在 A S D F / J K L ; の8レーン）
  - スマホ用は `scripts/touch_pad.gd`（TouchScreenButton＝マルチタッチ対応）を左右下に配置
- 縦横両対応。`scripts/screen.gd`（Autoload `Screen`）が向きに応じて基準解像度を 1280x720 / 720x1280 に切り替え、
  `Screen.layout_changed` で各画面がレイアウトを組み直す（stretch aspect=expand）
- タッチボタンはタッチ端末でのみ表示。配置はゲーム側が `touch_pad.place(rects)` で決める
- 日本語はWebでOSフォントが使えないため `assets/fonts/MPLUSRounded1c-Bold.ttf` をテーマで既定フォントにしている

## コマンド
- エディタ: `godot` （~/.local/bin/godot → ~/.local/opt/godot-4.7.2）
  - snap の `godot-4` は .NET(mono) 版なので使わない
- インポート: `godot --headless --import`
- Webエクスポート: `godot --headless --export-release "Web" build/web/index.html`
- ローカル確認: `python3 -m http.server 8000 -d build/web` → http://localhost:8000

## 公開
- URL: https://gentou30.github.io/maiddragoncasino/ （リポジトリ: Gentou30/maiddragoncasino, public）
- main に push すると `.github/workflows/pages.yml` が Web エクスポートして GitHub Pages にデプロイ
- シングルスレッド出力（thread_support=false）なので COOP/COEP ヘッダ不要

## 画像素材
- キャラクターは**ファーリー（ケモノ）向けデザイン**で作る。メイドドラゴンはマズルのあるピンクの擬人化ドラゴン、
  丸い体型（つるぷに）、黒白のメイド服。全年齢向けで性的な強調はしない。基準画像は `art/raw/maid_base.png`
- 生成: `tools/gen_image.sh <出力> "<プロンプト>" [参照画像...]`（Codex の image_generation を使い、
  `~/.codex/generated_images/` から回収する）。同じキャラの差分は基準画像を参照に渡して作る
- 透過: 緑(#00FF00)背景で生成し `tools/chroma_key.py` で抜く（`--split` でスプライトシートを分割）
- `art/raw/` は生成元の画像置き場（`.gdignore` でゲームには含めない）。ゲームで使うものは `assets/images/`
  - `maid_full.png`（タイトル立ち絵）/ `maid_{normal,happy,scheme,panic}.png`（HUDの表情）
  - `slot/*.png`（リール絵柄）/ `bg_casino.jpg`（背景）
- 見た目の共通設定（色・ネオンのパネル・ボタン・文字のふち取り）は `scripts/ui_style.gd`
- コードレビューやタスク委譲は Claude Code の Codex プラグイン（`/codex:review`, `/codex:rescue` 等）を使う
- 生成AI素材であることは公開時に明記する
