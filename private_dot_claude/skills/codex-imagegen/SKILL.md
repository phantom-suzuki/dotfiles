---
name: codex-imagegen
description: Codex CLI 経由で gpt-image-2 を呼び画像を生成する。アーキテクチャ図・UI モック・アイコン・バナー・イラスト・プレースホルダー画像等が必要な場面で使用。「画像を生成」「画像を作って」「画像生成」「gpt-image-2」「OpenAI Images」「アーキテクチャ図」「構成図を画像で」「architecture diagram」等のトリガーで発動。ChatGPT Plus / Pro / Business / Enterprise 以上のサブスクが前提。
---

# Codex Imagegen Skill

OpenAI Codex CLI の組み込み `$imagegen` ツール（gpt-image-2、2026-04-21 以降デフォルト）を使って画像を生成する。

## 起動条件

- 「画像を生成」「画像を作って」「PNG を作って」等の明示的な画像生成依頼
- 「アーキテクチャ図」「構成図」「ダイアグラム」を **画像** として欲しい場合（Mermaid で十分な場合は Mermaid を優先）
- 「UI モック」「ワイヤーフレーム」「アイコン」「バナー」「イラスト」「プレースホルダー画像」
- 「gpt-image-2」「DALL-E」「OpenAI Images」等の名指し

## 前提条件

- `codex` CLI がインストールされ、`codex login` で認証済み
- ChatGPT Plus / Pro / Business / Enterprise のいずれかのサブスクリプション（Free は不可）
- 通常の Codex usage limit を消費（テキスト処理比で 3-5x 速く消費）
- `OPENAI_API_KEY` 設定時は API 課金に切り替わる

## 基本コマンド

```bash
codex exec --sandbox workspace-write --skip-git-repo-check \
  '$imagegen [画像内容とスタイル] [絶対パス] に保存してください。' \
  < /dev/null
```

## 必須 3 要素（安定動作の鍵）

1. **`$imagegen` トリガー**: prompt の **先頭** に置く。組み込み画像生成ツールを起動する合図
2. **内容とスタイル**: 題材（例「ターミナルアイコン」「3層アーキテクチャ図」）に加え、スタイル（「フラットデザイン」「パステル配色」「16:9」「白背景」「クラウドアイコン風」等）を明示
3. **保存先絶対パス**: prompt **末尾** に「`/path/to/file.png` に保存してください」の形式で **絶対パス** を指定。相対パス不可

## 注意点

### アスペクト比指定
- ピクセル単位の厳密な制御は不安定
- アスペクト比指定（`16:9` / `1:1` / `9:16` 等）は比較的安定して反映される

### 生成時間
- 1 枚あたり 30 秒〜2 分

### 並列実行
- 2 枚以上を同時生成する場合は `run_in_background: true` で background 実行
- 完了通知後にファイル存在を `ls` 等で確認してから次のステップへ

### 副産物
- 生成過程で `~/.codex/generated_images/` に中間ファイルが蓄積される可能性あり
- 不要になったら適宜削除

## 使用例

### 例 1: アーキテクチャ図

```bash
codex exec --sandbox workspace-write --skip-git-repo-check \
  '$imagegen 3 層アーキテクチャ図を生成。フロントエンド（React）→ API（Node.js）→ DB（PostgreSQL）。フラットデザイン、16:9、白背景、青系配色、矢印で接続。/Users/foo/project/docs/architecture.png に保存してください。' \
  < /dev/null
```

### 例 2: アイコン（並列実行）

Claude Code 環境では `Bash` を `run_in_background: true` で 2 つ呼び、両方の完了通知を待つ。

```bash
# Background job 1
codex exec --sandbox workspace-write --skip-git-repo-check \
  '$imagegen ターミナルアイコン。フラットデザイン、パステル配色、1:1。/tmp/terminal-icon.png に保存してください。' \
  < /dev/null

# Background job 2
codex exec --sandbox workspace-write --skip-git-repo-check \
  '$imagegen データベースアイコン。フラットデザイン、パステル配色、1:1。/tmp/db-icon.png に保存してください。' \
  < /dev/null
```

## 失敗時の対応

| 症状 | 対応 |
|---|---|
| 画像が生成されない | prompt 先頭に `$imagegen` が含まれているか確認 |
| 保存パスが効かない | 絶対パスで指定（相対パス不可） |
| サンドボックスエラー | `--sandbox workspace-write` が指定されているか確認 |
| Git repo チェックで止まる | `--skip-git-repo-check` を付ける |
| レート制限 | 時間を空けて再実行、または `OPENAI_API_KEY` で API モードに切り替え |
| 認証エラー | `codex login` で再認証 |

## 参考

- [Codex CLI Features](https://developers.openai.com/codex/cli/features)
- [Image Generation in Codex CLI: gpt-image-2, the $imagegen Skill, and Visual Development Workflows](https://codex.danielvaughan.com/2026/04/27/codex-cli-image-generation-gpt-image-2-visual-development-workflows/)
- [Using Codex with your ChatGPT plan](https://help.openai.com/en/articles/11369540-using-codex-with-your-chatgpt-plan)
- [Codex CLI で gpt-image-2 を使う実装ガイド (note.com)](https://note.com/brave_quince241/n/nb0be3839a24f)
