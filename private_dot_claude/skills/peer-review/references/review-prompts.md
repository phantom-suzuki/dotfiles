# レビュアー別プロンプトテンプレート

peer-review は **Claude（L1）+ Codex（L2）** の 2 段構成。Gemini は `--with-gemini` で opt-in の第 3 レーン。

## L1/L2 の観点分担（重要）

| レイヤ | 強み | 主担当の観点 | 苦手 |
|--------|------|-------------|------|
| **L1 Claude (Opus)** | 大きなコンテキスト把握、ADR/Issue/Epic 横断、設計意図の理解 | architecture / spec-consistency / alternatives / goal-achievement（設計レベル） | 実コード細部の機械検証 |
| **L2 Codex** | リポジトリ実体への grep/sed 即時実行、構文・依存関係の機械検証 | security（実コード）/ goal-achievement（実装到達度）/ コード変更の整合性 | プロジェクト固有の設計意図 |

L1 プロンプトに「コード細部は L2 に任せ、設計意図に集中」と明示することで重複指摘を減らす。

---

## L1: Claude（セッション内）

Claude 自身（オーケストレーター）が俯瞰レビューを実施する。Opus 4.X（1M context）推奨。

### プロンプトに含めるもの

1. PR メタ情報（title / body / author / files / diff stats）
2. PR diff 全文（ファイルに保存して参照）
3. コンテキスト収集結果:
   - PR 本文で参照される Issue / Epic の本文
   - 関連 ADR / Spec の要点
   - 既存の同類ドキュメント（責務重複チェック用）
   - 対象領域の CLAUDE.md
   - 既存 CodeRabbit / 他レビュアーの指摘
4. [review-checklist.md](review-checklist.md) の俯瞰 5 観点
5. [classification-guide.md](classification-guide.md) の分類ルール
6. **L1 担当観点の明示**: 「architecture / spec-consistency / alternatives / goal-achievement（設計レベル）に集中する。実コード細部の grep ベース検証は L2 Codex が担当するので踏み込まない」

### 出力

`/tmp/peer-review-<PR>-l1.md` に以下を保存:

```markdown
# L1 Claude 俯瞰レビュー結果 — PR #<N>

## 指摘一覧

### must-fix
#### M1. [axis] タイトル
（内容）

### should-fix
#### S1. [axis] タイトル
...

### question
### nit
### praise

## 総評
（3-5 文）

## 判定
approve / comment / request-changes
```

---

## L2: Codex CLI（デフォルト）

Codex を独立したセカンドオピニオンとして呼び出す。`scripts/codex-review.sh` がラッパー。

### 呼び出し

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/codex-review.sh" <PR番号> [base-branch] > /tmp/peer-review-<PR>-l2.txt
```

`base-branch` を省略すると `gh pr view --json baseRefName` から自動取得。

### Codex の動作モデル

- `codex exec review --base <branch>` は **diff を base と比較してレビュー観点を自動生成**するため、カスタム PROMPT は不要（むしろ `--base` と PROMPT は **引数排他**）
- Codex は **リポジトリ内で grep/sed/git log 等を即時実行**して実コードを直接検証する。L1 Claude では届かない実装細部の整合性チェックに強い
- 出力は JSONL で多数の `command_execution` イベント + 最終 `agent_message`。`codex-review.sh` が `agent_message` を抽出する

### Codex 呼び出しの落とし穴（PR #386 の教訓）

| 落とし穴 | 対処 |
|---------|------|
| `--base + PROMPT` の引数排他 | カスタム PROMPT は渡さない |
| `--output-last-message` が空 | JSONL の `item.type=="agent_message"` を primary 抽出に使う |
| 多数の `command_execution` イベント | Codex がリポジトリを検証している正常動作。stderr へのログで把握 |
| ユーザー設定の影響 | 必ず `--ignore-user-config --ignore-rules` を付ける |

これらは `scripts/codex-review.sh` で吸収済み。直叩きは避ける。

---

## L3 (opt-in): Gemini CLI

Gemini を **追加の第 3 レーン** として呼び出す（`--with-gemini` 指定時のみ）。`scripts/gemini-review.sh` がモデルフォールバック内蔵。

### 注意: capacity 制約が頻発

Gemini Pro は `MODEL_CAPACITY_EXHAUSTED` で失敗することが多く、リトライ待ちで数分溶ける。スクリプトは Flash にフォールバックするが、Flash も失敗するケースがあるため、**通常は Codex で十分**。Gemini は以下のような場合に opt-in:

- ドキュメント PR で文体・トーンの追加意見が欲しい
- 設計レビューで複数の独立した視点を集めたい（Codex は実コード寄り）

### プロンプトテンプレート

```markdown
あなたは <プロジェクト名> の第三者レビュアーです。以下の PR に対して **俯瞰的観点** で独立したセカンドオピニオンを返してください。

# PR 情報
- PR: <owner>/<repo> #<N>
- タイトル: <title>
- 作成者: <author>
- 内容: <body 要約>
- 位置付け: <Epic/Issue との関係>

# Epic / 関連 Issue（親タスク）
<Epic 本文>

# 関連 Spec / ADR の要点
<ADR / Spec の要点を 200 字程度にサマライズ>

# 既存レビュー指摘
<CodeRabbit 等の既存指摘、あれば>

# レビュー観点（必須、俯瞰的）
1. **セキュリティ**
2. **アーキテクチャ・設計の良し悪し**
3. **目的達成（完了定義への到達度）**
4. **他に最善の案はないか**
5. **Spec/ADR との整合**

**細かい文言修正・typo は除外** してください。俯瞰的観点に絞ってください。

# 出力フォーマット

以下の JSON のみを出力してください（他のテキストは含めない）:

\`\`\`json
{
  "findings": [
    {
      "category": "must-fix" | "should-fix" | "nit" | "praise" | "question",
      "axis": "security" | "architecture" | "goal-achievement" | "alternatives" | "spec-consistency",
      "title": "1 行要約",
      "description": "詳細",
      "suggestion": "対処案"
    }
  ],
  "overall_judgment": "approve" | "comment" | "request-changes",
  "overall_summary": "俯瞰的な総評（3-5 文）"
}
\`\`\`

# diff 全文
<PR diff>
```

### 呼び出し

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/gemini-review.sh" <PR番号>
```

### モデルフォールバック

1. `gemini-2.5-pro` で試行
2. `MODEL_CAPACITY_EXHAUSTED` 等のエラーなら `gemini-2.5-flash` にフォールバック
3. 両方失敗時は L1+Codex のみで続行（リトライ待ちで数分溶かさない）

---

## プロンプト設計のポイント

### 俯瞰を強制する工夫

- 「**俯瞰的観点**」を複数回強調（プロンプト冒頭、観点リストの見出し）
- 「**細かい文言修正・typo は除外**」を明示
- 観点軸を 5 つに制限（増やすとノイズが増える）
- JSON 出力フォーマットで category / axis を強制

### Epic / ADR 要点の渡し方

- 全文コピペすると context 窓を圧迫するので、**200〜500 字程度の要点サマライズ**
- 特に **Epic 備考**は PR 本文に含まれない設計前提があるので必ず含める
- ADR は「ステータス（承認済み/提案中）」も含める

### 既存 CodeRabbit 指摘の渡し方

- 指摘の二重化を避けるため、「既存の CodeRabbit 指摘」セクションで明示
- 「**この指摘と重複しないよう、俯瞰観点に絞る**」と誘導

### L1/L2 の観点分担で重複を減らす

- L1 プロンプトで「実コード細部の grep ベース検証は L2 Codex が担当するので踏み込まない」と明示
- Codex はカスタム PROMPT を渡せないため、観点分担は **L1 プロンプト側で明示**する
