---
name: ui-visual-check
description: UI / UX を変更した PR に、Before/After のスクリーンショット比較を添付する。base ブランチと head ブランチの画面を同じ素材・同じ幅で撮影し、横並びの比較ページを作り、画像を専用ブランチ `visual-snapshots` に保存して PR コメントに貼る。「UI の PR にスクショを付けて」「ビジュアルチェック」「Before/After を PR に」「見た目の変更を確認したい」「デザイン変更のレビュー」等の依頼時、および CSS・テンプレート・レンダラ・画面コンポーネントを変更した PR を作る前に必ず使う（ユーザーが明示しなくても、UI を変えた PR には添付する運用）。
argument-hint: "[PR 番号 | head ブランチ] [--base main] [--no-comment] [--no-artifact]"
---

# UI Visual Check — UI 変更 PR の Before/After 添付

UI を変えた PR は、コードの diff とテストだけでは「見た目がどう変わったか」「設計どおりか」が伝わらない。
このスキルは、base と head を **同じ素材・同じ幅** で撮影して横並びにし、レビュアーが 1 画面で差を確認できる状態を PR に添付する。

2026-08-20 の artifact-gate PR #15 では、この手順でコードレビューとテストを通過した後に見た目の不具合を 2 件
（Mermaid 図の背景色・見出しの表示順）発見した。テストが通っていても撮影は省かない。

## 前提

| 必要なもの | 用途 |
|---|---|
| Playwright MCP（`mcp__playwright__browser_*`） | 撮影。`file:` URL は遮断されるため、ローカル HTTP で配信してから開く |
| `gh` CLI | PR コメントの投稿・PR 情報の取得 |
| `python3` | 比較ページ生成スクリプト（`scripts/build_compare.py`） |
| リポジトリ側の「固定素材を静的 HTML にする手段」 | 下記「素材の作り方」。無ければ Step 1 で用意する |

## 手順の全体像

```text
Step 0  対象の特定（PR 番号 / ブランチ、base）と撮影対象の決定
Step 1  素材を静的 HTML にする（base と head の両方、同じ固定素材で）
Step 2  ローカル HTTP で配信し、Playwright で撮影（幅ごと）
Step 3  撮影結果を自分の目で確認し、設計とのズレを列挙する（ここが本番）
Step 4  ズレがあれば修正 → head だけ撮り直し
Step 5  比較ページを生成し、画像を visual-snapshots ブランチへ保存
Step 6  PR コメントに添付（必要なら Artifact も）
```

## Step 0: 対象の特定

- 引数が PR 番号なら `gh pr view <N> --json headRefName,baseRefName,files` で head / base / 変更ファイルを取る。ブランチ名なら base は `--base`（既定 `main`）
- 変更ファイルから **撮影すべき画面** を決める。レンダラや共通 CSS の変更なら、その CSS を使う全画面種別（例: レポート閲覧・一覧・ログイン画面）。1 画面だけの変更ならその画面
- 幅は既定で **1280px（デスクトップ）**。レイアウトが幅に反応する変更なら **390px（モバイル）** も加える
- head と base はそれぞれ別の worktree に展開する（`git worktree add <scratchpad>/base <base>`）。main の作業ツリーは触らない

## Step 1: 素材を静的 HTML にする

撮影は「実サーバーを起動して本番相当の URL を開く」より、**描画関数を直接呼んで静的 HTML を書き出す**方が再現性が高く、認証や外部 API に依存しない。

### 素材の作り方（優先順）

1. **リポジトリに素材スクリプトがある場合**（推奨。例: `npm run visual:fixtures -- --out <dir>`）: base と head の各 worktree で同じコマンドを実行し、出力先を分ける
2. **無い場合**: head の描画関数を呼ぶ小さなエントリを書き、バンドラ（esbuild 等）で束ねて node で実行する。base と head で関数のシグネチャが違うなら、エントリを 2 本書く。このとき **素材スクリプトをリポジトリに追加する提案** を PR に含める（次回から手順 1 で済む）
3. **描画関数が切り出せない場合**（SPA 等）: 開発サーバーを base / head の worktree で別ポートに起動し、同じ URL を撮影する。認証が要る画面は、テスト用のバイパスやシード済みセッションを使う

固定素材（Markdown・JSON 等）は、**変更点が表れる要素を網羅**したものを 1 つ用意する。レポート表示なら、見出し階層・表・引用・リスト・コードブロック・図（Mermaid 等）・リンク・長い 1 行を含める。

素材ファイル名は `<画面>-before.html` / `<画面>-after.html` のように、後で対応が分かる名前にする。

## Step 2: 撮影

```bash
# 出力ディレクトリを HTTP で配信（Playwright MCP は file: を開けない）
cd <out-dir> && python3 -m http.server 8765 --bind 127.0.0.1 >/dev/null 2>&1 &
```

Playwright MCP で、画面ごとに次を繰り返す:

1. `browser_resize`（幅 1280 × 900。モバイルは 390 × 844）
2. `browser_navigate`（`http://127.0.0.1:8765/<file>.html`）
3. Web フォントやクライアント描画（Mermaid・ハイライト）がある場合は `browser_wait_for` で 3〜4 秒待つ
4. `browser_take_screenshot`（`fullPage: true`、`scale: "css"`、`filename: "NN-<画面>-<before|after>.png"`）

撮影後の PNG は **現在の作業ディレクトリ（多くはリポジトリ直下）に書き出される**。すぐ scratchpad の `shots/` へ移動する（リポジトリに untracked の PNG を残さない）。撮り終えたら `browser_close` とサーバー停止（`pkill -f "http.server 8765"`）を忘れない。

ファイル名は番号 + 画面 + before/after で揃える（例: `01-report-before.png` / `02-report-after.png`）。比較ページ生成スクリプトはこの命名でペアを組む。閲覧者名ありやモバイル幅のような派生状態は `NN-<画面>-after-<派生>.png`（例: `06-report-after-mobile.png`）とし、単独画像として並べる。

## Step 3: 目視確認（本番）

撮影した after の画像を Read で開き、**設計文書（デザインシステム・モック）と見比べて**ズレを列挙する。観点:

- 設計で決めた順序・位置（例: タイトルの直下にメタ情報）になっているか
- 共通 CSS の副作用（例: `pre` の背景色が図の `pre` にも当たっている）
- フォントが読み込まれているか（フォールバックに落ちていないか）
- 幅 390px で横スクロールが本文全体に出ていないか
- 文字色と背景のコントラスト、リンクと本文の区別

見つけたズレは「何が / 設計ではどうあるべきか / どこを直すか」の 3 点で書き、修正を実装役に依頼する（自分で直す場合は小さな変更に留める）。

## Step 4: 修正後の撮り直し

修正を取り込んだら head の素材を再生成し、**after だけ**撮り直す（before は変えない）。番号・ファイル名は同じにして上書きする。

## Step 5: 比較ページと保存先

```bash
python3 ~/.claude/skills/ui-visual-check/scripts/build_compare.py \
  --shots <shots-dir> --out <shots-dir>/compare.html \
  --title "PR #<N> <要約> Before/After" \
  --base <base> --head <head> \
  --note "<画面名>=<変更点の説明>" ...
```

- `--embed` を付けると画像を data URI で埋め込んだ自己完結 HTML になる（Artifact 公開用）
- ペアは `NN-<画面>-before.png` と `NN+1-<画面>-after.png` を自動で組む。`-after` だけのものは単独画像として並べる

画像の保存先は **履歴を共有しない専用ブランチ `visual-snapshots`**（orphan）にする。main の履歴に PNG を混ぜないため。

```bash
# 初回のみ: git worktree add --orphan -b visual-snapshots .worktrees/visual-snapshots
# 2 回目以降: git worktree add .worktrees/visual-snapshots visual-snapshots
cd .worktrees/visual-snapshots && mkdir -p pr-<N> && cp <shots-dir>/*.png <shots-dir>/compare.html pr-<N>/
git add -A && git commit -m "chore: add visual snapshots for PR #<N>" && git push -u origin visual-snapshots
```

`.worktrees/` はリポジトリの `.git/info/exclude` に登録しておく（`.gitignore` を汚さない）。

## Step 6: PR への添付

PR コメントは `gh pr comment <N> --body-file <file>` で投稿する（本文はファイル経由。コマンド文字列に日本語を埋めない）。構成:

1. 撮影条件（素材・幅・base / head・保存先ブランチ）と比較ページへのリンク
2. **目視確認で見つけて直した問題**（件数と内容、修正コミット）。0 件なら「問題なし」と明記
3. 画面ごとに Before | After の 2 列テーブル。画像は `https://github.com/<owner>/<repo>/blob/visual-snapshots/pr-<N>/<file>.png?raw=true`
4. 画像が表示されない場合の代替（比較ページ・Artifact）

非公開リポジトリでは `?raw=true` の画像がコメント内で表示されない可能性がある。Artifact（`--embed` 版を publish）を併記して、どちらかで必ず見られる状態にする。Artifact を publish するときは `artifact-design` スキルの規律に従う。

### PR コメントの雛形

```markdown
## UI ビジュアルチェック（Before / After）

<素材と条件を 1〜2 文>。画像は `visual-snapshots` ブランチの `pr-<N>/`。横並びの比較ページ: <URL>

### ビジュアルチェックで見つけて直した問題（<件数> 件）
1. <何が> → <どう直したか>（<SHA>）

### <画面名>
| Before（<base>） | After（<head>） |
| --- | --- |
| ![](<before URL>) | ![](<after URL>) |
```

## 完了報告

ユーザーには次を報告する: 撮影した画面と幅 / 目視で見つけた問題と修正 / PR コメントと比較ページの URL / 素材スクリプトをリポジトリに追加したか（追加を提案したか）。

## 落とし穴（実測）

| 事象 | 対応 |
|---|---|
| `browser_navigate` が `file:` を拒否する | `python3 -m http.server` で配信して `http://127.0.0.1:<port>/` を開く |
| スクショがリポジトリ直下に落ちる | 撮影直後に scratchpad へ `mv`。`git status` で untracked が無いことを確認 |
| Mermaid / Web フォントが描画前に撮れる | `browser_wait_for` で 3〜4 秒待つ。`startOnLoad` の描画完了はテキスト待ちでは検出しにくい |
| zsh の `noclobber` で `>` の上書きが失敗する | 出力ファイルを `rm -f` してから実行する |
| base に素材スクリプトが無い | head のスクリプトを base の worktree にコピーして試す。シグネチャ違いで失敗したら base 用エントリを別に書く |

## 関連

- `~/.claude/skills/ui-compare/` — 画像群から比較 HTML を作る汎用スキル（本スキルの Step 5 はその型を踏襲）
- `~/.claude/skills/self-review/` — コード観点のセルフレビュー。UI 変更 PR では self-review と本スキルの両方を通す
- `~/.claude/skills/parallel-work-decision/` — worktree の扱い
