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

## 関連

- GitHub Primer color tokens: <https://primer.style/foundations/color>
- Mermaid 公式: <https://mermaid.js.org/syntax/flowchart.html#classes>
