---
description: >-
  Gemini CLI・Codex CLI・Claude Code を組み合わせたセルフレビュースキル。
  Simplify でコード品質を改善した後、外部レビュアーで指摘を収集し、
  指摘がなくなるまでループする。判断が必要な項目は開発者に確認する。
  「セルフレビュー」「レビュー回して」「self-review」等の依頼時に使用。
argument-hint: "[--max-iterations N] [--strategy auto|cascade|parallel] [--scope changed|staged|all] [--skip-simplify] [--skip-external]"
---

# Skill: /self-review

## 概要

Simplify（コード品質改善）と外部レビュアー（バグ・設計問題検出）を交互に実行し、
指摘がなくなるまでイテレーションするセルフレビュースキル。
イテレーションごとに自動コミットし、最終的にスカッシュマージされる前提で履歴を残す。

## パラメータ

| パラメータ | デフォルト | 説明 |
|-----------|----------|------|
| `--max-iterations` | 5 | 最大ループ回数 |
| `--strategy` | `auto` | `auto`（diff規模で自動判定）/ `cascade`（精度優先・直列）/ `parallel`（速度優先・並列） |
| `--scope` | `changed` | `changed`（ベースブランチからの差分）/ `staged`（ステージ済み）/ `all`（全ファイル） |
| `--skip-simplify` | false | Simplify をスキップ |
| `--skip-external` | false | 外部レビューをスキップ（Simplify のみ実行） |

## 前提条件

- Git リポジトリ内で実行すること
- 以下の CLI が利用可能であること（なければ自動スキップ）:
  - `gemini` (Gemini CLI)
  - `codex` (Codex CLI)
  - `claude` (Claude Code、`-p` モードで外部レビュアーとして使用)

## 実行手順

### Step 0: 初期化

1. Git リポジトリであることを確認する:
   ```bash
   git rev-parse --git-dir >/dev/null 2>&1 || { echo "Git リポジトリ内で実行してください"; exit; }
   ```
2. パラメータを解析する（未指定はデフォルト値）
3. 利用可能なレビュアーを検出する:
   ```bash
   command -v gemini && echo "gemini: available"
   command -v codex && echo "codex: available"
   command -v claude && echo "claude: available"
   ```
3. `--scope` に応じて対象ファイルを特定する:
   - `changed`: `git diff --name-only $(git merge-base HEAD main)..HEAD` （main がなければ develop を試行）
   - `staged`: `git diff --cached --name-only`
   - `all`: 全トラッキングファイル
4. 対象ファイルがなければ「レビュー対象がありません」と報告して終了
5. `--strategy auto` の場合、diff 規模で戦略を決定する:
   - diff 行数 ≤ 200 かつ ファイル数 ≤ 5 → `parallel`
   - それ以外 → `cascade`
6. 初回のみ [references/classification-guide.md](references/classification-guide.md) を読み込み、分類ルールを把握する（以降のイテレーションでは再読み込み不要）
7. 初期状態をユーザーに報告する:
   - 対象ファイル一覧
   - 選択された strategy
   - 利用可能なレビュアー
   - max-iterations

### Step 1: Simplify 実行

`--skip-simplify` でなければ、Simplify エージェントのロジックを適用する。

1. 対象ファイルに対して、コード品質の自律改善を実行する:
   - コードの再利用性チェック（既存ユーティリティとの重複）
   - 不要な複雑さの除去
   - 効率性の改善（パフォーマンスボトルネック等）
2. CLAUDE.md に記載されたプロジェクト規約に準拠させる
3. 変更があったファイルを記録する

### Step 2: Simplify 結果のコミット

Step 1 で変更があった場合のみ:

```bash
git add <changed-files>
git commit -m "refactor: self-review iteration N - simplify"
```

変更がなかった場合はスキップ。

### Step 3: 外部レビュー実行

`--skip-external` でなければ、外部レビュアーを実行する。

#### strategy: cascade（精度優先・直列）

以下の優先順位で**最初に成功したレビュアーの結果を採用**する。
前のレビュアーが失敗（レート制限、タイムアウト等）した場合のみ次に進む。

1. **Claude Code** (`claude -p`): [references/review-prompts.md](references/review-prompts.md) の Claude 用プロンプトを使用
2. **Codex CLI** (`codex review`): [references/review-prompts.md](references/review-prompts.md) の Codex 用コマンドを使用
3. **Gemini CLI**: `${CLAUDE_SKILL_DIR}/scripts/gemini-review.sh` を実行（リトライ・モデルフォールバック内蔵）

各レビュアーの呼び出し方法とプロンプトは [references/review-prompts.md](references/review-prompts.md) を参照。

#### strategy: parallel（速度優先・並列）

Gemini と Codex を**同時に実行**し、結果をマージする。
Claude-p は Simplify と同じモデルファミリーのため parallel では使わない。

1. Gemini と Codex を並列で起動（Agent ツールで並列実行）
2. 両方の結果を統合し、重複する指摘を除去する

#### レビュアーが全滅した場合

全レビュアーが失敗した場合は、ユーザーに状況を報告し、Simplify の結果のみで続行するか確認する。

### Step 4: 指摘の分類

外部レビューの結果を [references/classification-guide.md](references/classification-guide.md) に基づいて分類する。

| カテゴリ | 条件 | アクション |
|---------|------|-----------|
| **auto-fix** | 修正方法が明確で、機能変更を伴わない | 即座に修正を適用 |
| **judgment** | 複数の選択肢がある、設計判断を伴う | ユーザーに確認 |
| **info** | 参考情報、将来の改善提案 | ログに記録のみ |

### Step 5: 修正の適用

#### 5-1. サマリ報告

まず分類結果の概要をテキストで報告する:
- auto-fix / judgment / info の件数
- 各カテゴリの主要な指摘の概要（1行ずつ）

#### 5-2. auto-fix の自動適用

auto-fix 項目を自動修正する。

#### 5-3. judgment 項目の対話的解決

judgment 項目は **AskUserQuestion ツールの選択 UI** で **1件ずつ** ユーザーに確認する。

質問の書き方ルール:
- **question**: 概念的に「何が問題で、どういう選択肢があるか」を説明する。物理名（ファイル名、行番号、Step 番号等）は補足に留め、中身を詳細に把握していなくても技術的判断力で選べるレベルの抽象度にする
- **header**: 問題の概念を端的に（例: 「DB選定」「認証方式」、12文字以内）
- **option label**: 短く概念的（例: 「キャッシュ追加」「現状維持」）
- **option description**: 具体的な影響・トレードオフを補足。必要なら物理名もここに含める
- 推奨案がある場合は先頭に置き `(Recommended)` を付ける

1件の回答を得てから次の judgment に進む。全件完了後に修正を適用する。

#### 5-4. info 項目

info 項目は最終サマリに含める（対話的な確認はしない）。

### Step 6: レビュー修正のコミット

Step 5 で変更があった場合のみ:

```bash
git add <changed-files>
git commit -m "fix: self-review iteration N - review fixes"
```

### Step 7: 収束判定

以下の条件で次のイテレーションに進むか判定する:

| 条件 | アクション |
|------|-----------|
| Step 1 (Simplify) で変更あり **または** Step 3 (外部レビュー) で auto-fix/judgment 指摘あり | → 次のイテレーションへ（Step 1 に戻る） |
| 両方とも変更/指摘なし | → **収束完了**、Step 8 へ |
| max-iterations に到達 | → **上限到達**、Step 8 へ（残存指摘を報告） |

### Step 8: 最終サマリ出力

[templates/review-summary.md](templates/review-summary.md) のテンプレートに基づいてサマリを出力する。

内容:
- 総イテレーション数
- 各イテレーションの概要（Simplify 変更数、レビュー指摘数、修正数）
- 使用したレビュアーと strategy
- 残存する info 項目（将来の改善提案）
- 終了理由（収束完了 / 上限到達）

## エラーハンドリング

| エラー | 原因 | 対応 |
|--------|------|------|
| Gemini 429 (MODEL_CAPACITY_EXHAUSTED) | サーバー容量不足 | scripts/gemini-review.sh が自動リトライ → モデルフォールバック → 次のレビュアーへ |
| Codex レート制限 | 5時間ウィンドウ超過 | 次のレビュアーへフォールバック |
| Claude-p タイムアウト | ネットワークまたはAPI負荷 | 120秒タイムアウトで次のレビュアーへ |
| 全レビュアー失敗 | 全CLIが利用不可 | ユーザーに報告、Simplify 結果のみで判断を仰ぐ |
| git コミット失敗 | pre-commit hook 等 | エラー内容を表示し、ユーザーに対応を確認 |

## 注意事項

- このスキルはセッション内で Claude がオーケストレーターとして各ツールを呼び出す設計
- 外部レビュアー (`claude -p`, `codex`, `gemini`) は別プロセスとして起動される
- Simplify はセッション内で直接コード修正を行う
- コンテキストウィンドウの消費を抑えるため、3イテレーション以上続く場合は `/compact` の実行を検討する
