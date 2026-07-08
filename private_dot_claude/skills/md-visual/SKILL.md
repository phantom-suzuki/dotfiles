---
name: md-visual
description: Markdown ドキュメント（計画・ロードマップ・レポート・提案等）を、claude.ai の Artifact として閲覧できる「視覚版」の自己完結 HTML に起こして publish する。「Markdown から視覚版を作って」「この plan を視覚化して」「ロードマップを見やすく」等の依頼時に使用。Markdown を SoT（ソース）、HTML を生成ビュー（ビルド成果物）として扱い、二重管理にしない。既存 Artifact の URL を渡された場合は同一 URL に再デプロイして最新 MD に追従させる。
---

# md-visual — Markdown を視覚版 Artifact に起こす

Markdown ドキュメントを、装飾された閲覧用の Artifact（claude.ai ホストの Web ページ）に変換する。

## 中核の考え方（重要）

- **Markdown = SoT（唯一の正本）。HTML = そこから生成したビュー（ビルド成果物）**。両者を二重管理しない。
- HTML はソースとして編集しない。**内容を変えるときは必ず MD を直し、再生成する**。
- 視覚版はスナップショットであり MD と自動同期しない。「最新にして」と言われたら MD を読み直して再生成する。

## 手順

### 1. 設計スキルを先に読む（必須）
Artifact を作る前に **`artifact-design` スキルを必ず起動**し、対象ドキュメントに見合った treatment（装飾の度合い）を判断する。計画・レポートは基本 utilitarian（情報設計重視・過剰装飾しない）。

### 2. MD を読み、構造と主役の数字を抽出
- 見出し階層・表・箇条書き・結論を把握する。
- **主役の数字（KPI / 結論）を特定**し、ページ冒頭で先に見せる（summary before detail）。
- **MD にない数値・事実を創作しない**。視覚版は MD の忠実なレンダリングであること。

### 3. 情報設計として組む（ドキュメントではなく計器盤）
- 冒頭: eyebrow + タイトル + 結論の thesis（最も重要な1数字）+ KPI 行。
- 本文: セクションごとに表・積み上げバー・カード等で「走査できる」形に。
- 状態は色 + 形で二重符号化（pill / チップ / severity ストライプ）。semantic 色（good/warn/critical）はアクセント色とは別に持つ。
- 数字が縦に揃う箇所は `font-variant-numeric: tabular-nums`。

### 4. 自己完結で作る（Artifact の CSP 制約）
- **外部リソース禁止**: CDN スクリプト・外部フォント・リモート画像・fetch はすべてブロックされる。CSS/JS はインライン、画像は data URI。
- **Web フォントは link しない**（サイレントフォールバックの罠）。system font stack（`ui-sans-serif` / `ui-monospace` 等）で強いヒエラルキーを作るか、必要なら @font-face の data URI。
- ページ本体は横スクロールさせない。**表・コード・図は `overflow-x:auto` の内側**に入れる。
- レスポンシブ（相対単位・flex/grid + gap・`max-width:100%`）。フォーカス可視・`prefers-reduced-motion` 尊重。
- `<!doctype>` / `<html>` / `<head>` / `<body>` は書かない（publish 時に付与される）。ページ内容だけを書く。

### 5. publish する
- Artifact ツールで publish。`file_path` に生成 HTML、`favicon` に絵文字1〜2個（**再デプロイ間で不変に保つ**）、`description` に1文の要約。
- **新規**: そのまま publish → URL が発行される。
- **既存を最新化**: ユーザーから Artifact の URL を渡されたら、`url` パラメータに渡して**同一 URL へ再デプロイ**（MD 追従）。同一セッションで作った Artifact は同じ `file_path` で再 publish すれば同 URL に更新される。
- ソースの MD ファイルパスをユーザーに併せて伝える（SoT はこちら、と明示）。

## 出力物の置き場

- 生成 HTML は原則 scratchpad（一時領域）に置く。**リポジトリに恒久同梱したい**と明示された場合のみ、MD と同じディレクトリに `<md-basename>.html` として置き、MD ヘッダーに「この HTML は MD から生成したビュー」と注記する。

## やってはいけないこと

- MD にない結論・数値の捏造。
- HTML を SoT 扱いして MD と乖離させる（HTML だけ直して MD を放置）。
- 外部フォント/CDN の link（CSP で落ちて無装飾になる）。
- ページ本体の横スクロール（表は必ず overflow コンテナに入れる）。

## 関連

- `artifact-design`（treatment 判断・タイポ/配色/レイアウトの原則。本スキルの前段で必ず起動）
- Artifact ツール（publish・同一 URL への再デプロイ）
</content>
