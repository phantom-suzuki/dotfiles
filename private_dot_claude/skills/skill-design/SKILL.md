---
description: Claude Code スキルの設計・構造設計を支援する。Progressive Disclosure、参照ファイル分離、安全原則、フロントマター設計等のベストプラクティスに基づくガイド。「スキル設計」「SKILL.md を書く」「スキル構成を考えたい」等の依頼時に使用。
---

# Skill Design Guide

Claude Code スキルの設計原則とベストプラクティス。
公式ドキュメント、Anthropic リファレンス実装、公式ガイドに基づく。

## Progressive Disclosure（段階的開示）

スキルの情報を 3 層に分離し、必要なときだけコンテキストに読み込む。
これがスキル設計の最も重要なアーキテクチャ原則。

| 層 | 内容 | トークンコスト | タイミング |
|----|------|:---:|---|
| Layer 1 | frontmatter（description） | ~100 tokens | 常時（セッション開始時） |
| Layer 2 | SKILL.md 本文 | < 5,000 tokens 推奨 | スキル発火時 |
| Layer 3 | references/, scripts/, templates/ | 必要時のみ | Claude が Read で取得 |

## サイズ制約

| 項目 | 推奨値 | 根拠 |
|------|--------|------|
| SKILL.md 行数 | **500 行以下** | 公式ドキュメント |
| SKILL.md 語数 | 1,500-2,000 語、最大 3,000 語 | plugin-dev skill-development |
| description | 250 文字以下 | typeahead でトランケートされる |
| Step 数 | 8-10 以下 | 超える場合は参照ファイルへの委譲を検討 |

コンテキストウィンドウは共有リソース。SKILL.md が長いほど会話・ツール結果に使える余地が減り、後半の Step の実行精度が低下する。

## ファイル構成パターン

### 公式リファレンス実装（plugin-dev/hook-development）

```
skill-name/
├── SKILL.md                    # ワークフロー概要 + Step 間遷移（< 500 行）
├── references/                 # 詳細手順・パターン集（必要時のみ Read）
│   ├── patterns.md
│   ├── advanced.md
│   └── migration.md
├── examples/                   # テンプレート・使用例
├── scripts/                    # 実行スクリプト（Read ではなく実行）
├── agents/                     # サブエージェント定義
└── templates/                  # 出力テンプレート
```

### 参照ファイルのルール

- SKILL.md から **1 階層のみ** 参照する。ネストすると Claude が部分読みする
- 100 行超の参照ファイルには冒頭に目次を置く
- SKILL.md からの参照方法:

```markdown
## Step 3: Organization 基盤チェック

詳細な手順は [references/org-foundation.md](references/org-foundation.md) を参照して実行する。
```

- `${CLAUDE_SKILL_DIR}` で移植可能なパス参照が可能:

```markdown
Run: python ${CLAUDE_SKILL_DIR}/scripts/validate.py
```

### 使い分け

| ディレクトリ | 用途 | コンテキスト消費 |
|-------------|------|:---:|
| references/ | 詳細手順、API リファレンス、パターン集 | Read 時のみ |
| examples/ | 出力例、使用例 | Read 時のみ |
| templates/ | 生成するファイルのテンプレート | Read 時のみ |
| scripts/ | バリデーション、レポート生成 | **消費しない**（実行のみ） |
| agents/ | サブエージェント定義 | Agent 起動時のみ |

## SKILL.md の構造テンプレート

### Frontmatter

```yaml
---
description: <250 文字以下。冒頭にスキルの目的、末尾にトリガーフレーズ>
---
```

| フィールド | 必須 | 説明 |
|-----------|:----:|------|
| description | Yes | typeahead 検索・自動発火に使用 |
| name | No | **省略推奨**。ディレクトリ名がフォールバック。typeahead プレフィックス検索との互換性のため |
| context | No | `fork` でサブエージェント実行 |
| agent | No | context: fork 時のエージェントタイプ（Explore 等） |
| disable-model-invocation | No | true で Claude の自動発火を抑制（ユーザー手動のみ） |
| user-invocable | No | false で Claude 専用スキル |
| allowed-tools | No | 使用可能ツールの制限 |

### 本文セクション

```markdown
# Skill: /namespace:skill-name

## 概要
  1-2 段落でスキルの目的・スコープ

## パラメータ
  テーブル形式（パラメータ名、必須、デフォルト、説明）

## 実行手順
  ### Step N: ステップ名
  各 Step は概要 + 判断ロジック。
  詳細手順が長い場合は「references/xxx.md を参照して実行」と記載。

## エラーハンドリング
  テーブル形式（エラー、原因、対応）

## 関連ドキュメント
  リンクリスト
```

## スキル間連携

スキルから別スキルを直接呼び出す機構は存在しない。
Claude がオーケストレーターとして連携する。

| パターン | 説明 | 用途 |
|---------|------|------|
| 参照ファイル分離 | SKILL.md → references/ を Read で段階的に取得 | 1 スキル内の複雑なフロー |
| サブエージェント | agents/ にエージェント定義を配置 | 分析・評価の委譲 |
| context: fork | スキルをサブエージェントとして分離実行 | 独立した重い処理 |
| ユーザーオーケストレーション | Claude が次のスキル実行を提案 | スキル間の連携 |

### 分割の判断基準

**分割する**:
- SKILL.md が 500 行を超える → references/ に詳細を分離
- 独立して再実行したいフェーズがある → 別スキルに分離
- デバッグ時に問題箇所の特定が困難 → フェーズごとに分離

**まとめる**:
- Step 間で強い状態依存がある
- ユーザー体験としてワンコマンドが自然
- 8-10 Step 以内に収まる

## 安全原則（破壊的操作の防止）

外部 API の登録・更新・削除系操作全般に適用する原則。

| # | 原則 | 説明 |
|---|------|------|
| 1 | **Read-before-Write** | 変更前の状態を必ず取得してから変更を実行する |
| 2 | **差分表示 + 確認** | 変更内容を事前にユーザーに提示し、確認を得てから実行する |
| 3 | **追加優先** | 全置換 API でも既存データを保全した上で追加分だけを差分適用する |
| 4 | **復元可能性の確保** | 変更前の状態をログ/キャッシュに保存し、復元手順を用意する |
| 5 | **冪等実行** | 「存在チェック → 不足分のみ作成」を徹底する |

削除系・全置換系操作は、ユーザーの明示的確認なしに実行しない。

## description の書き方

description はスキル発見の鍵。以下を意識する:

1. **冒頭にスキルの目的**を簡潔に書く（「何をするスキルか」が 1 文でわかる）
2. **末尾にトリガーフレーズ**を含める（「〇〇」「△△」等の依頼時に使用）
3. 250 文字以内に収める（超えるとトランケート）
4. キーワードを詰め込みすぎない（自然な文として読める範囲で）

良い例:
```
リポジトリのスクラム環境をワンコマンドでセットアップする。Organization 基盤チェックから Sprint Board 作成、.scrum/ 配置までを実行。「セットアップ」「スクラム導入」等の依頼時に使用。
```

## 出典

- [Extend Claude with skills](https://code.claude.com/docs/en/skills) -- 公式ドキュメント
- [Skill authoring best practices](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices) -- Anthropic Platform Docs
- [anthropics/claude-code plugins/](https://github.com/anthropics/claude-code/tree/main/plugins) -- 公式リファレンス実装
- [anthropics/claude-plugins-official](https://github.com/anthropics/claude-plugins-official) -- 公式プラグインディレクトリ
- [The Complete Guide to Building Skills for Claude](https://resources.anthropic.com/hubfs/The-Complete-Guide-to-Building-Skill-for-Claude.pdf) -- Anthropic 公式ガイド（33 ページ）
- [Skill Collaboration Pattern](https://www.mindstudio.ai/blog/claude-code-skill-collaboration-pattern) -- MindStudio
- [Four-Pattern Framework](https://www.mindstudio.ai/blog/four-pattern-framework-claude-code-skills) -- MindStudio
