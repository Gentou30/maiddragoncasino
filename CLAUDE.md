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

## 技術スタック
- Godot 4.7.2（公式・非.NET版）、GDScript のみ（C#はWeb出力不可）、Compatibility レンダラー
- 1280x720、stretch=canvas_items
- 入力は `_input()` のイベントベースで処理し、演出（Tween等）で入力を止めない

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
- Codex で生成（`codex exec` の image_generation）。この環境ではCodexのサンドボックスが保存に失敗するため、
  `~/.codex/generated_images/<session>/` から `assets/images/` にコピーする
- コードレビューやタスク委譲は Claude Code の Codex プラグイン（`/codex:review`, `/codex:rescue` 等）を使う
- 生成AI素材であることは公開時に明記する
