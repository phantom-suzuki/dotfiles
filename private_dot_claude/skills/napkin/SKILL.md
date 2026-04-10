---
name: napkin
description: Napkin AI でMarkdownドキュメントからビジュアル（図表・インフォグラフィック）を生成する。「図を作って」「ビジュアル化して」「Napkinで」などの依頼時に使用。
argument-hint: "[file-or-text] [--style style] [--format format]"
---

# Napkin AI Visual Generation Skill

Markdown ドキュメントやテキストから Napkin AI でプロフェッショナルなビジュアルを生成する。

## Arguments

- `$ARGUMENTS` — Optional: `[source] [--style style] [--format format]`
  - `/napkin` → インタラクティブモード（対象を質問）
  - `/napkin docs/design/scaling-strategy.md` → 指定ファイルのビジュアル化セクションを抽出・生成
  - `/napkin "Deparuの負荷対策は5層構造で..."` → テキストを直接ビジュアル化
  - `/napkin docs/design/ --style corporate` → ディレクトリ内の全Markdownを処理

## Prerequisites

- `NAPKIN_API_KEY` が `~/.claude/settings.json` の `mcpServers.napkin-ai.env` に設定済みであること

APIキー未設定の場合:
> Napkin AI APIキーが設定されていません。
> 1. https://app.napkin.ai でアカウント作成
> 2. Account Settings → Developers → APIトークン生成
> 3. `~/.claude/settings.json` の `mcpServers.napkin-ai.env.NAPKIN_API_KEY` に設定
> 4. Claude Code を再起動

## Procedure

### 1. ソースの解決

`$ARGUMENTS` を解析して入力ソースを決定:

| 入力 | 動作 |
|------|------|
| ファイルパス (`.md`) | ファイルを読み込み、ビジュアル化セクションを抽出 |
| ディレクトリパス | 配下の `.md` ファイルを一覧表示し、ユーザーに選択を求める |
| クオート文字列 | テキストを直接ビジュアル化 |
| 引数なし | カレントプロジェクトの `docs/` を探索し候補を提示 |

### 2. ビジュアル化セクションの抽出

Markdownファイルから以下の方法でビジュアル化対象を特定する:

#### 方法A: マーカー付きセクション（優先）

```markdown
<!-- napkin:start id="unique-id" style="corporate" -->
ビジュアル化したいテキスト
<!-- napkin:end -->
```

マーカーから `id`, `style`, `format` 属性をパース。

#### 方法B: マーカーなしの場合

ファイル全体を分析し、ビジュアル化に適したセクションを提案:
- アーキテクチャ説明（システム構成、フロー）
- 比較表・一覧
- タイムライン・手順
- 数値データ・計算式

ユーザーに候補を提示して選択してもらう。

### 3. 出力先の決定

画像の保存先はプロジェクトルート相対で決定（**絶対パスではなく CWD 基準**）:

1. マーカーに `id` があれば → `docs/images/napkin/{id}.{format}`
2. ファイル名 + セクション見出しから推定 → `docs/images/napkin/{file-stem}-{section}.{format}`
3. 出力ディレクトリが存在しない場合は作成:

```bash
mkdir -p docs/images/napkin
```

### 4. 生成方式の選択

**MCP サーバーを優先し、失敗時は API フォールバックを使用する。**

#### 方式A: MCP サーバー経由（優先）

Napkin AI MCP Server のツールが利用可能かチェック:

1. MCP ツール `generate_visual` または `generate_and_save` を呼び出す
2. 成功した場合:
   - MCP がローカル保存した場合 → 保存先を確認
   - MCP が URL を返した場合 → Step 5 の curl ダウンロードで保存
3. 失敗した場合 → 方式B にフォールバック

#### 方式B: API 直接呼び出し（フォールバック）

MCP が利用不可または失敗した場合、Bash + curl で Napkin AI API を直接呼び出す。

**APIキーの取得:**

```bash
NAPKIN_API_KEY=$(cat ~/.claude/settings.json | jq -r '.mcpServers["napkin-ai"].env.NAPKIN_API_KEY')
```

**Step 4-1: ビジュアル生成リクエスト送信**

```bash
RESPONSE=$(curl -s -X POST "https://api.napkin.ai/v1/visual" \
  -H "Authorization: Bearer ${NAPKIN_API_KEY}" \
  -H "Content-Type: application/json" \
  -d '{
    "format": "png",
    "content": "<抽出したテキスト>",
    "language": "ja",
    "style_id": "<スタイルID>",
    "color_mode": "light"
  }')

REQUEST_ID=$(echo "$RESPONSE" | jq -r '.id')
echo "Request ID: $REQUEST_ID"
```

**Step 4-2: ステータスポーリング（最大60秒）**

```bash
for i in $(seq 1 30); do
  STATUS_RESPONSE=$(curl -s "https://api.napkin.ai/v1/visual/${REQUEST_ID}/status" \
    -H "Authorization: Bearer ${NAPKIN_API_KEY}")
  STATUS=$(echo "$STATUS_RESPONSE" | jq -r '.status')
  echo "Status: $STATUS (attempt $i/30)"
  if [ "$STATUS" = "completed" ]; then
    break
  elif [ "$STATUS" = "failed" ]; then
    echo "ERROR: Generation failed"
    echo "$STATUS_RESPONSE" | jq .
    break
  fi
  sleep 2
done
```

**Step 4-3: 画像ダウンロード**

```bash
FILE_URL=$(echo "$STATUS_RESPONSE" | jq -r '.generated_files[0].url')
mkdir -p docs/images/napkin
curl -s -o "docs/images/napkin/<output-filename>.png" \
  -H "Authorization: Bearer ${NAPKIN_API_KEY}" \
  "$FILE_URL"
```

**生成に失敗した場合:**
- 401 エラー → APIキーの確認を案内
- 429 エラー → レート制限、少し待ってリトライ
- その他 → エラー内容を表示してユーザーに判断を委ねる

### 5. Markdownへの画像参照挿入

生成成功後、元のMarkdownに画像参照を挿入（またはユーザーに挿入案を提示）:

#### マーカー付きの場合

`<!-- napkin:end -->` の直後に:
```markdown
![{id}](./images/napkin/{id}.png)
```

#### マーカーなしの場合

挿入位置と参照テキストをユーザーに提案:
```markdown
この位置に以下を挿入することを提案します:
![アーキテクチャ概要](./images/napkin/scaling-architecture.png)
```

**ユーザーの承認なしに既存のMarkdownファイルを編集しないこと。**

### 6. 結果レポート

生成完了後、以下を報告:

```markdown
**Napkin AI ビジュアル生成完了**

| 項目 | 値 |
|------|-----|
| ソース | `docs/design/scaling-strategy.md` |
| セクション | アーキテクチャ概要 |
| スタイル | Corporate Clean |
| 生成方式 | MCP / API フォールバック |
| 出力 | `docs/images/napkin/scaling-architecture.png` |

Markdownへの参照挿入:
`![アーキテクチャ概要](./images/napkin/scaling-architecture.png)`
```

## Options

| オプション | デフォルト | 説明 |
|-----------|----------|------|
| `--style` | (Napkin AI デフォルト) | ビジュアルスタイル（名前 or ID） |
| `--format` | `png` | 出力形式: `png`, `svg`, `ppt` |
| `--dry-run` | false | 生成せずにプレビュー（抽出結果のみ表示） |
| `--api` | false | MCP をスキップして API 直接呼び出しを強制 |

### 利用可能なスタイル

#### Colorful（カラフル）
| スタイル名 | style_id | 説明 |
|-----------|----------|------|
| Vibrant Strokes | `CDQPRVVJCSTPRBBCD5Q6AWR` | 鮮やかな線のフロー |
| Glowful Breeze | `CDQPRVVJCSTPRBBKDXK78` | 陽気な色の渦 |
| Bold Canvas | `CDQPRVVJCSTPRBB6DHGQ8` | 活気ある形のフィールド |
| Radiant Blocks | `CDQPRVVJCSTPRBB6D5P6RSB4` | ソリッドカラーの広がり |
| Pragmatic Shades | `CDQPRVVJCSTPRBB7E9GP8TB5DST0` | ブレンド色調パレット |

#### Casual（カジュアル）
| スタイル名 | style_id | 説明 |
|-----------|----------|------|
| Carefree Mist | `CDGQ6XB1DGPQ6VV6EG` | 穏やかなトーン |
| Lively Layers | `CDGQ6XB1DGPPCTBCDHJP8` | 柔らかな色のレイヤー |

#### Hand-drawn（手描き）
| スタイル名 | style_id | 説明 |
|-----------|----------|------|
| Artistic Flair | `D1GPWS1DCDQPRVVJCSTPR` | 手描きカラースプラッシュ |
| Sketch Notes | `D1GPWS1DDHMPWSBK` | 自由な手描きスタイル |

#### Formal（フォーマル）
| スタイル名 | style_id | 説明 |
|-----------|----------|------|
| Elegant Outline | `CSQQ4VB1DGPP4V31CDNJTVKFBXK6JV3C` | 洗練されたアウトライン |
| Subtle Accent | `CSQQ4VB1DGPPRTB7D1T0` | プロフェッショナルな淡い色使い |
| Monochrome Pro | `CSQQ4VB1DGPQ6TBECXP6ABB3DXP6YWG` | 単色フォーカス |
| Corporate Clean | `CSQQ4VB1DGPPTVVEDXHPGWKFDNJJTSKCC5T0` | ビジネス向けフラット |

#### Monochrome（モノクロ）
| スタイル名 | style_id | 説明 |
|-----------|----------|------|
| Minimal Contrast | `DNQPWVV3D1S6YVB55NK6RRBM` | クリーンなモノクロ |
| Silver Beam | `CXS62Y9DCSQP6XBK` | グレースケール |

## Examples

```
# 特定ファイルのビジュアル化セクションを生成
/napkin docs/design/scaling-strategy.md

# テキストを直接ビジュアル化
/napkin "1. ユーザーがリクエスト送信 2. ALBが振り分け 3. ECSで処理 4. RDSに保存"

# スタイル指定
/napkin docs/design/scaling-strategy.md --style corporate

# ドライラン（何が生成されるか確認）
/napkin docs/design/scaling-strategy.md --dry-run

# SVG形式で生成
/napkin docs/design/scaling-strategy.md --format svg

# API直接呼び出しを強制（MCP不調時）
/napkin docs/design/scaling-strategy.md --api
```

## Rules

- **ユーザーの承認なしに既存ファイルを編集しない** — 画像参照の挿入は必ず提案してから
- **APIクレジットを節約する** — 不必要な再生成を避ける。`--dry-run` の活用を促す
- **画像は `docs/images/napkin/` に集約** — プロジェクトごとの CWD 相対パスで保存
- **マーカー構文を推奨する** — 再生成時の冪等性を確保するため
- **MCP 優先、API フォールバック** — MCP が動作しない場合のみ API 直接呼び出しに切り替え
- **生成画像をgitにコミットする場合**、コミットメッセージは `docs: generate napkin visual for {section}` の形式
