# Mermaid Diagram Conventions

GitHub Markdown / ドキュメントに Mermaid 図を埋め込むときは、**ダーク/ライト両モードで視認可能なカラールール** に従うこと。背景色のみ指定して文字色を default に任せると、GitHub のダークモードでノード内テキストが背景に埋もれる。

## カラールール（必須）

Mermaid の `classDef` でノード色を指定する場合、**`color` を必ず明示**する。`fill` だけ指定して `color` を省略してはならない。

### 推奨パレット（GitHub Primer emphasis 系）

| 状態 | fill | stroke | color | 用途 |
|---|---|---|---|---|
| Done / 完了 | `#1a7f37` | `#1a7f37` | `#ffffff` | success.emphasis |
| In Progress / 進行中 | `#bf8700` | `#9a6700` | `#ffffff` | attention 系 |
| Warning / 警告 | `#cf222e` | `#82071e` | `#ffffff` | danger.emphasis |
| Info / 情報 | `#0969da` | `#0969da` | `#ffffff` | accent.emphasis |
| Default / 通常 | （指定なし） | （指定なし） | （指定なし） | Mermaid テーマ任せ（両モード自動対応） |

WCAG AA コントラスト比（4.5:1）以上を満たす設計。

### 実装例

```mermaid
graph LR
  A[Done node] --> B[In Progress] --> C[Warning]
  classDef done fill:#1a7f37,stroke:#1a7f37,color:#ffffff;
  classDef inprog fill:#bf8700,stroke:#9a6700,color:#ffffff;
  classDef warn fill:#cf222e,stroke:#82071e,color:#ffffff;
  class A done;
  class B inprog;
  class C warn;
```

### Don't

- ❌ `classDef done fill:#9fdf9f;` — パステル色は明るすぎ、`color` 省略でダークモードに弱い
- ❌ `classDef warn fill:#ffb3b3;` — 同上
- ❌ 文字色を default に任せる — `color:#ffffff` を明示しないとダークモードで埋もれる

## 凡例の併記（推奨）

色覚多様性への配慮と可読性確保のため、Mermaid 図の **直前にカラールールの凡例を 1 行で併記** する:

```markdown
> カラールール: 🟢 Done / 🟡 In Progress / 🔴 Warning / 通常ノードは Mermaid デフォルト
```

色だけでは区別できない場合、ノード内テキストに `✅ Done` / `⚠️ 警告` 等のアイコンを併用する。

## ダイアグラム種別の選び方

| 用途 | 推奨 |
|---|---|
| 状態遷移 / フロー / 依存関係 | `graph LR` または `graph TD` |
| 時系列 / 並行処理 | `sequenceDiagram` |
| データ構造 / Class 関係 | `classDiagram` |
| 工程表 / ガントチャート | `gantt` |
| ER 図 | `erDiagram` |

`graph LR` は横長になるため、ノード数が 5 以上で深い依存がある場合は `graph TD` のほうが読みやすい場合もある。

## 描画検証（Mermaid 追加・変更時は push 前に必須）

GitHub は Mermaid をクライアント側でレンダリングし、**CI も CodeRabbit も Mermaid の構文を検証しない**（CodeRabbit はレンダリングせず APPROVED を出す）。構文エラーは PR 差分ビューで人が目視するまで分からない。よって **Mermaid を追加・変更したら push する前に `mermaid.parse()` で構文検証する**。

検証レシピ（一時ディレクトリで実行）:

セッションの system prompt に scratchpad ディレクトリの案内があればそこを使う。案内がない場合は `mktemp -d` で一時ディレクトリを作る。`/tmp/mmcheck` のような固定パスを使い回さない（複数セッションが並行すると、同じディレクトリ・依存関係を取り合って競合するため）。

```bash
WORKDIR="$(mktemp -d)/mmcheck"   # scratchpad ディレクトリの案内があればそちらのパスに置き換える
mkdir -p "$WORKDIR" && cd "$WORKDIR"
npm init -y >/dev/null 2>&1 && npm install mermaid@11 jsdom --no-audit --no-fund >/dev/null 2>&1
cat > check.mjs <<'EOF'
import { JSDOM } from 'jsdom';
import { readFileSync } from 'fs';
const dom = new JSDOM('<!DOCTYPE html><body></body>', { pretendToBeVisual: true });
global.window = dom.window; global.document = dom.window.document;
const mermaid = (await import('mermaid')).default;
mermaid.initialize({ startOnLoad: false });
const def = readFileSync(process.argv[2], 'utf8');   // ```mermaid ブロックの中身だけを渡す
try { await mermaid.parse(def); console.log('PASS'); }
catch (e) { console.log('FAIL: ' + String(e.message || e).split('\n').slice(0,3).join(' | ')); process.exit(1); }
EOF
node check.mjs <抽出した .mmd ファイル>
```

### 既知の落とし穴

- **`stateDiagram-v2` の別行 `class A,B name` 文 + 日本語ステート ID はレキサーで落ちる**（`Lexical error ... Unrecognized text`）。`class A,B name;` 形式は本来 flowchart の機能で stateDiagram のグラマーには無い。状態遷移を描くなら **`graph LR` / `graph TD`（flowchart）+ ASCII node ID + 日本語ラベル `id[日本語]`** にし、`classDef`/`class` は本ドキュメントの実装例パターンを使う（日本語 ID 問題も同時に回避できる）。

## 関連

- GitHub Primer color tokens: <https://primer.style/foundations/color>
- Mermaid 公式: <https://mermaid.js.org/syntax/flowchart.html#classes>
