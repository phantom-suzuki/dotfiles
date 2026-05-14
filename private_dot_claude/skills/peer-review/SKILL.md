---
description: >-
  他者が作成した Pull Request を俯瞰的観点（セキュリティ / アーキテクチャ / 目的達成 /
  代替案 / Spec 整合）でレビューするスキル。Claude Opus（L1）+ Codex CLI（L2）の
  2 段構成で独立したセカンドオピニオンを収集し、指摘を統合して PR にコメント投稿する。
  「PR レビュー」「peer review」「ピアレビュー」「他者の PR を見て」等の依頼時に使用。
argument-hint: "[pr-number-or-url] [--skip-codex] [--with-gemini] [--post-mode comment|approve|request-changes]"
---

# Skill: /peer-review

## 概要

`self-review` が **自分のコード** のイテレーション型セルフレビュー（修正ループあり）であるのに対し、`peer-review` は **他者の PR** の俯瞰的レビュー（修正なし、コメント投稿のみ）を担当する。

`review-pr` が「自分が受けたレビューコメントへ返信する側（reviewee）」であるのに対し、`peer-review` は「他者の PR をレビューする側（reviewer）」。

### 対比サマリ

| | self-review | review-pr | **peer-review** |
|---|---|---|---|
| 対象 | 自分の変更 | 自分が受けたレビュー | **他者の PR** |
| 修正権限 | あり（自動コミット） | あり（コメント対応） | **なし**（コメント投稿のみ） |
| イテレーション | 収束までループ | レビュー対応 | **1 パスのみ** |
| 重視する観点 | バグ・品質 | 指摘への対応 | **設計・目的達成・代替案** |
| レビュアー戦略 | cascade/parallel | — | **Claude(L1) + Codex(L2)** |

## レビュアーの観点分担

L1 と L2 は **異なる強み** を持つため、観点を分担することで重複指摘とノイズを減らす。

| レイヤ | 強み | 主担当の観点 | 苦手 |
|--------|------|-------------|------|
| **L1 Claude (Opus)** | 大きなコンテキスト把握、ADR/Issue/Epic 横断、設計意図の理解 | architecture / spec-consistency / alternatives / goal-achievement（設計レベル） | 実コード細部の機械検証 |
| **L2 Codex** | リポジトリ実体への grep/sed 即時実行、構文・依存関係の機械検証、コード変更の論理整合 | security（実コード）/ goal-achievement（実装到達度）/ コード変更の整合性 | プロジェクト固有の設計意図・ステークホルダーコンテキスト |

L1 プロンプトには「コード細部は L2 に任せ、設計意図に集中」と明示。
L2 (Codex) は `codex exec review --base <branch>` の標準観点に任せ、独立した第三者視点として扱う。

## パラメータ

| パラメータ | デフォルト | 説明 |
|-----------|----------|------|
| `pr-number-or-url` | (必須) | レビュー対象 PR（番号 or URL） |
| `--skip-codex` | false | L2 Codex をスキップ（L1 Claude のみ） |
| `--with-gemini` | false | Gemini を追加（Codex に加えて第 3 のセカンドオピニオン。capacity 制約があるため通常は不要） |
| `--post-mode` | `comment` | 投稿モード。`comment` / `approve` / `request-changes` |

## 前提条件

- Git リポジトリ内で実行
- 以下が利用可能:
  - `gh` (GitHub CLI、認証済み)
  - `codex` (Codex CLI、`--skip-codex` でなければ必須)
  - `jq` (JSON パース用)
  - `gemini` (Gemini CLI、`--with-gemini` 指定時のみ必須)
- レビュー対象 PR が accessible であること

## 実行手順

### Step 0: 初期化とパラメータ解析

1. Git リポジトリ確認:
   ```bash
   git rev-parse --git-dir >/dev/null 2>&1 || { echo "Git リポジトリ内で実行してください"; exit; }
   ```
2. `pr-number-or-url` を PR 番号に正規化（URL なら末尾から抽出）
3. 利用可能 CLI 検出: `gh`, `codex`, `jq`, `gemini` (`--with-gemini` 時のみ必須)
4. 初回のみ以下を読み込む:
   - [references/context-collection.md](references/context-collection.md) — コンテキスト収集手順
   - [references/review-checklist.md](references/review-checklist.md) — 俯瞰観点
   - [references/classification-guide.md](references/classification-guide.md) — 指摘分類
   - [references/posting-guide.md](references/posting-guide.md) — 投稿ガイド
5. 初期状態をユーザーに報告（PR 情報、選択レビュアー、post-mode）

### Step 1: コンテキスト収集

[references/context-collection.md](references/context-collection.md) に従い、**俯瞰レビューに必須のコンテキスト**を収集する。

最低限収集すべき情報:

1. **PR メタ情報**: `gh pr view <N> --json title,body,files,commits,baseRefName,headRefName,reviewRequests,reviews,labels,milestone`
2. **PR diff**: `gh pr diff <N>`
3. **PR 本文で参照される Issue / Epic**: 本文から `#\d+` を抽出し `gh issue view <N>` で取得
4. **関連 ADR / Spec**: PR 本文 / diff 内で参照される `.md` ファイルを Read
5. **既存の同類ドキュメント**: 対象ファイルと同ディレクトリの関連ドキュメント（例: dns-domain.md 更新なら ses.md も読む）を Read
6. **CLAUDE.md（該当領域）**: 対象ディレクトリの CLAUDE.md（infra/CLAUDE.md 等）
7. **既存レビュー**: CodeRabbit 等の既存レビューコメント（重複指摘を避ける）

### Step 2: L1 Claude 俯瞰レビュー（設計・コンテキスト担当）

Claude 自身（Opus 推奨、1M context）で俯瞰レビューを実施する。

**L1 の担当観点**: architecture / spec-consistency / alternatives / goal-achievement（設計レベル）。
**L1 が踏み込まないこと**: 実コード細部の検証（grep でしか分からない依存関係、関数間の整合性、テスト網羅性）。これらは L2 Codex が独立に検証する。

[references/review-checklist.md](references/review-checklist.md) の 5 観点軸（security / architecture / goal-achievement / alternatives / spec-consistency）で評価し、[references/classification-guide.md](references/classification-guide.md) に基づき分類する。

L1 を非対話で `claude -p` に投げる場合は以下のフラグを必須とする（self-review と同方針）:

- `--bare`（hooks/skills/MCP/CLAUDE.md/auto-memory の自動ロード抑止、起動高速化＋再現性）
- `--output-format json --json-schema "${CLAUDE_SKILL_DIR}/references/schemas/finding-schema.json"`（指摘構造の固定）

出力: `/tmp/peer-review-<PR>-l1.json`（schema 準拠、findings + summary）。
対話的に Opus 上で直接レビューする場合はこのフラグは不要だが、L1/L2 のマージ容易性のため最終的に同 schema に揃えること。

### Step 3: L2 Codex セカンドオピニオン（実コード担当）

`--skip-codex` でなければ、`scripts/codex-review.sh` で Codex CLI を呼び出す。

呼び出し:
```bash
bash "${CLAUDE_SKILL_DIR}/scripts/codex-review.sh" <PR番号> [base-branch] > /tmp/peer-review-<PR>-l2.txt
```

`base-branch` を省略した場合は `gh pr view` から自動取得。

**L2 (Codex) の担当観点**: 実コードへの grep/sed を即時実行して、コード変更の整合性・実装到達度・実装レベルのセキュリティリスクを独立に検証する。

**Codex 呼び出しの落とし穴**（PR #386 の教訓）:

- `--base <branch>` と PROMPT は **併用不可**（codex CLI の引数排他）。よってカスタム指示は渡さず、`codex exec review` の標準観点に任せる。プロジェクト固有のコンテキストは L1 Claude 側で扱う
- `--ignore-user-config --ignore-rules` を必ず付けて、ユーザー設定や `.rules` ファイルの差異を排除する
- `--output-last-message <file>` で最終メッセージを取得できるが、**ファイルが空のまま返ることがある**。JSONL の `item.type=="agent_message"` を primary、`--output-last-message` を fallback として抽出する（`codex-review.sh` がこの抽出を担当）
- 実行中に **多数の `command_execution` イベント**が JSONL に流れる（PR #386 では 19 コマンド）。これは Codex がリポジトリ実体を機械検証している正常動作。stdout には抽出済みの最終 agent_message のみが出力される

#### Gemini を使う場合（opt-in）

`--with-gemini` 指定時のみ、`scripts/gemini-review.sh` を追加で呼び出す。Pro → Flash のモデルフォールバック内蔵。

ただし **Gemini Pro は capacity 制約で失敗が多発する**ため、デフォルトでは使わない。リトライ待ちで数分溶ける場合は早めに kill して L1+L2 のみで続行する判断をする（PR #386 の教訓）。

```bash
cat prompt.md | bash "${CLAUDE_SKILL_DIR}/scripts/gemini-review.sh" <PR番号> > /tmp/peer-review-<PR>-gemini.json
```

プロンプトは [references/review-prompts.md](references/review-prompts.md) の Gemini 用テンプレート。

### Step 4: 指摘の統合と分類

L1 (schema 準拠 JSON) と L2 (Codex agent_message のテキスト) の指摘を統合する。

1. **Codex の結論を解釈**: Codex の `agent_message` は構造化 JSON ではなく自然文の場合が多い。「no actionable issues」「actionable な指摘なし」等の場合は **L1 の指摘を L2 が否定していない** とみなし、L1 単独で進める。Codex が具体的な指摘を出した場合は L1 と axis/対象でマージ
2. **重複除去**: 同一 axis + 同一対象（同一ファイル ±5 行）の指摘は 1 件にマージ、L1/L2 の両者が指摘していた旨を記録
3. **分類格上げ/格下げ**: L1/L2 で classification が異なる場合、[references/classification-guide.md](references/classification-guide.md) の判断フローに従う。**Codex が独立に否定した指摘は格下げを検討**（must-fix → should-fix、should-fix → nit）
4. **判定**: must-fix が設計の核心に関わる → `request-changes` 候補 / must-fix が文言修正レベル → `comment` 候補 / 指摘なし or praise のみ → `approve` 候補

L1 が schema 違反した場合は手動補正、Codex が異常応答（agent_message なし）した場合は L1 単独で続行する。

### Step 5: ドラフト作成

**原則: 指摘ごとに行コメントへ分離、トップコメントはサマリに絞る**（CodeRabbit 形式）。

#### トップコメント
[templates/top-comment.md](templates/top-comment.md) のテンプレートに沿って `/tmp/pr<PR>-comments/top.md` に作成:
1. 冒頭の謝意と総評（2-3 文）
2. 良かった点（praise 列挙）
3. **指摘サマリ**（件数 + 簡易タイトルのみ、詳細は「行コメント参照」と誘導）
4. 総評（判定理由）
5. レビュー方法の補足（折りたたみ details）

#### 行コメント
各指摘 1 件 = 行コメント 1 件として `/tmp/pr<PR>-comments/{M1,M2,S1,...}.md` に個別ファイルとして書き出す。ヘッダー行に分類とタイトル（例: `**[must-fix / M1] ...**`）、本文に「該当箇所・背景・影響・対処案」を書く。

#### 行指定できない指摘
PR 本文の表現、全体方針、PR 間の整合性などは**トップコメントに直接記載**する（行に無理矢理紐付けない）。

詳細は [references/posting-guide.md](references/posting-guide.md) の「行コメント vs トップコメント」「JSON 構築レシピ」参照。

### Step 6: ユーザー対話承認（必須）

**投稿前に必ずユーザー承認を取る**（他者に見える行為のため、`git-safety.md` の原則に準拠）。

対話パターン [references/posting-guide.md](references/posting-guide.md) に従う:

- **推奨**: 1 件ずつ指摘を解説し「PR 実装者にフィードバックするか」を判断してもらう
- 一度「推奨通り」の指示があれば、残りは一括で推奨対応を報告
- 用語解説が必要な場合は日常語から段階的に（例: DMARC rua → メール認証の基礎から）
- 最終確認: AskUserQuestion で投稿可否・判定・内容最終確認

### Step 7: PR 投稿

承認後、**Pull Request Reviews API** でトップコメント + 行コメントをアトミックに投稿する（`gh pr review` は行コメント未サポート）:

```bash
# /tmp/peer-review-<PR>-review.json を jq で組み立て（posting-guide.md 参照）
gh api --method POST /repos/<owner>/<repo>/pulls/<PR>/reviews --input /tmp/peer-review-<PR>-review.json
```

JSON 構造:
```json
{
  "event": "COMMENT" | "APPROVE" | "REQUEST_CHANGES",
  "body": "<トップコメント>",
  "comments": [
    {"path": "<file>", "line": N, "side": "RIGHT", "body": "<行コメント>"}
  ]
}
```

行コメントが不要な場合（俯瞰指摘のみ、極小 PR 等）は従来の `gh pr review --comment/--approve/--request-changes` も可。

投稿後の検証:
```bash
gh pr view <PR> --json reviews --jq '.reviews[-1] | {author, state, submittedAt}'
```

### Step 8: 最終サマリ

[templates/review-summary.md](templates/review-summary.md) のテンプレートに従い、作業サマリを表示する。

## エラーハンドリング

| エラー | 原因 | 対応 |
|--------|------|------|
| Codex `--base と PROMPT の併用不可` | 引数排他 | カスタム PROMPT は渡さず、`codex exec review --base` の標準観点に任せる。プロジェクト固有のコンテキストは L1 側で扱う |
| Codex `agent_message` が空 | Codex が結論を出さずに終了 | `codex-review.sh` が `--output-last-message` ファイルを fallback として読む。それでも空の場合は L1 単独で続行 |
| Gemini Pro `MODEL_CAPACITY_EXHAUSTED` | サーバー容量不足 | `scripts/gemini-review.sh` が Flash に自動フォールバック。Flash も失敗ならスキップして L1+Codex で続行（リトライ待ちで数分溶かさない） |
| Gemini 全モデル失敗 | キャパ / ネットワーク | `--with-gemini` は opt-in なので、失敗時は静かに諦めて L1+Codex で続行 |
| `gh pr review` が `--body-file` 未対応 | 古い gh バージョン | `--body "$(cat <file>)"` で代替 |
| 大規模 PR（diff > 3000 行） | コンテキスト窓圧迫 | ファイルごとに分割レビュー or 重要ファイルのみ対象化 |
| `AskUserQuestion` 承認なしで投稿 | 禁止 | 必ず承認を取る。ユーザーが「全て推奨で」と言っても、最終投稿前の明示確認は省略しない |

## 注意事項

- **投稿は破壊的操作に準じる**: 他者に見える行為のため、ユーザー承認なしに `gh pr review` を実行しない
- **CodeRabbit 既存指摘との棲み分け**: CodeRabbit は行レベル具体、peer-review は俯瞰。重複する場合は「refer（賛同）」「対応方針の確定促進」に留め、指摘の二重化を避ける
- **対話型判断が基本**: 指摘を一覧で出して「どれを採用する？」と聞くより、1 件ずつ解説しながら判断を仰ぐ方が、ユーザーの理解度・納得度・指摘の精度が上がる
- **L1/L2 の観点分担を守る**: L1 Claude は設計・コンテキスト、L2 Codex は実コード検証。両者で同じ観点を二重に動かすと重複指摘とノイズが増える。「Claude が実コード細部を grep する」「Codex に設計意図を解釈させる」のはアンチパターン
- **Codex 呼び出しは `codex-review.sh` 経由**: 直叩きすると `--base + PROMPT` 排他エラーや agent_message 抽出の差異で時間を溶かす。スクリプトを更新したい場合は scripts/ 側を直す
- **任意の代替経路**: `openai/codex-plugin-cc` プラグイン導入済みなら `/codex:review --background --base <ref>` で session 管理付き呼び出しに切り替え可能（次フェーズで本実装に統合する想定）
- **`self-review` や `review-pr` と混同しないこと**: 3 者は対象も操作も異なる
- **文体**: 日本語、敬体、github-conventions.md 準拠。CodeRabbit への言及は日本語で OK（返信ではなく言及なので）
