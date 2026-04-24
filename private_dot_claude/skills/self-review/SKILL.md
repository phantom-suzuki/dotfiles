---
description: >-
  Gemini CLI・Codex CLI・Claude Code を組み合わせたセルフレビュースキル。
  Simplify でコード品質を改善した後、外部レビュアーで指摘を収集し、
  指摘がなくなるまでループする。判断が必要な項目は開発者に確認する。
  「セルフレビュー」「レビュー回して」「self-review」等の依頼時に使用。
argument-hint: "[--max-iterations N] [--strategy auto|cascade|parallel|parallel-by-aspect] [--scope changed|staged|all] [--skip-simplify] [--skip-external] [--deep]"
---

# Skill: /self-review

## 概要

Simplify（コード品質改善）と外部レビュアー（バグ・設計問題検出）を **1 パス（既定）** で実行する軽量セルフレビュースキル。
所要時間とセッション消費を抑えることを最優先する。重厚な反復レビューは `--deep` で明示的に切り替える。

**デフォルト動作**:
- 1 イテレーションで完結（Simplify → 外部レビュー並列 → 修正適用 → 1 コミット）
- judgment 項目は **全件まとめて** AskUserQuestion の multiQuestion で一括提示
- 中間コミットは作らず、最後に 1 コミットだけ作成

## パラメータ

| パラメータ | デフォルト | 説明 |
|-----------|----------|------|
| `--max-iterations` | 1 | 最大ループ回数。通常は 1 パスで十分。反復したい場合のみ 2 以上を指定 |
| `--strategy` | `auto` | `auto`（diff規模で自動判定）/ `cascade`（精度優先・直列）/ `parallel`（速度優先・並列）/ `parallel-by-aspect`（大規模向け・観点別並列） |
| `--scope` | `changed` | `changed`（ベースブランチからの差分）/ `staged`（ステージ済み）/ `all`（全ファイル） |
| `--skip-simplify` | false | Simplify をスキップ |
| `--skip-external` | false | 外部レビューをスキップ（Simplify のみ実行） |
| `--deep` | false | 重厚モード: `--max-iterations 5 --strategy cascade` を自動適用 |

## 前提条件

- Git リポジトリ内で実行すること
- 以下の CLI が利用可能であること（なければ自動スキップまたはフォールバック）:
  - `gemini` (Gemini CLI、外部レビュアー)
  - `codex` (Codex CLI、**Simplify の委譲先兼** 外部レビュアー)
  - `claude` (Claude Code、`-p` モードで外部レビュアーとして使用)
  - `jq` (Gemini レビュー結果の JSON パースに使用)

## 実行手順

### Step 0: 初期化

1. Git リポジトリであることを確認する:
   ```bash
   git rev-parse --git-dir >/dev/null 2>&1 || { echo "Git リポジトリ内で実行してください"; exit; }
   ```
2. パラメータを解析する（未指定はデフォルト値）
3. 利用可能なレビュアーを検出する:
   ```bash
   command -v gemini && echo "gemini: bin found"
   command -v codex && echo "codex: bin found"
   command -v claude && echo "claude: bin found"
   ```

3.5. **Gemini プリフライト（容量不足の事前検知）**:
   `gemini` バイナリが存在する場合のみ、軽量プローブで実際に応答するかを先に確認する。
   容量不足 (429) 頻発時に本番レビューで最大 ~70s 浪費するのを避けるため。
   ```bash
   export GEMINI_STATUS=$(bash "${CLAUDE_SKILL_DIR}/scripts/gemini-preflight.sh" 2>/dev/null || echo "unavailable")
   ```
   結果の扱い:
   - `available` → Gemini を通常通り使用（pro → flash フォールバック）
   - `flash-only` → pro はスキップし flash のみで動作（`gemini-review.sh` が `GEMINI_STATUS` を参照）
   - `unavailable` → Gemini を利用可能レビュアーから除外する（以降のすべての strategy で Gemini をスキップ）

   **クールダウン**: 過去 15 分以内に 429 を検知した場合、プリフライトはプローブを省略して
   即 `unavailable` を返す（`~/.claude/skills/self-review/.gemini-cooldown` の mtime で判定）。
   短時間に self-review を連続実行するケースで無駄なプローブを省く。
4. `--scope` に応じて対象ファイルを特定する:
   - `changed`: `git diff --name-only $(git merge-base HEAD main)..HEAD` （main がなければ develop を試行）
   - `staged`: `git diff --cached --name-only`
   - `all`: 全トラッキングファイル
5. 対象ファイルがなければ「レビュー対象がありません」と報告して終了
6. `--strategy auto` の場合、diff 規模で戦略を決定する（**速度優先**: 大半のケースで parallel になるよう閾値を引き上げてある）:
   - diff 行数 ≤ 500 かつ ファイル数 ≤ 10 → `parallel`（デフォルト想定、2 レビュアー並列）
   - 500 < diff 行数 ≤ 2000 または 10 < ファイル数 ≤ 40 → `parallel-by-aspect`（**観点別並列**、3 レビュアーで bug/security/design を分担）
   - それ以外（diff > 2000 行 または ファイル > 40） → `cascade`
   - `--deep` 指定時は閾値に関わらず `cascade` を強制、`--max-iterations` も 5 に上書き
7. `classification-guide.md` は通常 **読み込まない**（分類は外部レビュアー側で済ませているため）。
   明らかな誤分類が多発する場合のみ [references/classification-guide.md](references/classification-guide.md) を読み込んで手動補正する
8. 初期状態をユーザーに報告する:
   - 対象ファイル一覧
   - 選択された strategy
   - 利用可能なレビュアー
   - max-iterations

### Step 1: Simplify 実行（原則 Codex CLI に委譲）

`--skip-simplify` でなければ Simplify を実行する。

**原則: `codex exec` に委譲する（T2 タスク扱い、Opus のコンテキストを節約）**。
Codex が使えない場合のみ Opus 自身の `/simplify` にフォールバックする。

#### 1-1. Codex CLI で実行（デフォルト経路）

`command -v codex` が成功する場合、以下のコマンドで委譲する:

```bash
cd <repo-root> && codex exec --full-auto --sandbox workspace-write "$(cat <<'EOF'
## タスク
以下の対象ファイルに対して Simplify を実行する。

## コンテキスト
対象ファイル:
<TARGET_FILES を改行区切りで埋め込む>

ベースブランチ: <BASE_BRANCH>
リポジトリ内に CLAUDE.md がある場合はそれに従うこと。

## 実施内容
- コードの再利用性: 既存ユーティリティとの重複があれば置換する
- 不要な複雑さの除去（早期 return、ネスト削減、冗長な中間変数の整理など）
- 効率性の改善（N+1、不要なループ、無駄なアロケーション）

## 制約
- public API の互換性を壊さない
- テストを変更する必要がある大幅なリファクタは行わない（judgment に任せる）
- **git add / commit / push は一切実行しないこと**（Opus 側で最終的に 1 コミットにまとめる）
- 変更したファイルの一覧を最後に箇条書きで出力すること
EOF
)"
```

完了したら Opus は `git diff --stat` で差分の規模を確認し、異常（対象外ファイルが変わっている等）
がないかだけチェックする。diff 本体を全件精読はしない（コンテキスト節約）。

#### 1-2. Codex が使えない場合のフォールバック

`codex` が未インストール、またはレート制限・timeout 等で失敗した場合:

- Opus 自身で `/simplify` スキルを対象ファイルに対して実行する
- 機能は 1-1 と同等: 再利用性チェック、複雑さ除去、効率性改善

#### 1-3. 結果の記録

どちらの経路でも、変更があったファイルの一覧だけを記録しておく（Step 6 のコミット対象になる）。

### Step 2: Simplify 結果の記録（コミットはしない）

Step 1 で変更があった場合、**stash や中間コミットを作らずそのまま Step 3 に進む**。
中間コミットは廃止した（理由: squash 前提で無駄な履歴が増え、rebase も煩雑になるため）。
最終コミットは Step 6 で一括作成する。

`--max-iterations >= 2` の場合のみ、イテレーション境界を明示する目的で中間コミット
（`refactor: self-review iteration N - simplify`）を作成する。

### Step 3: 外部レビュー実行

`--skip-external` でなければ、外部レビュアーを実行する。

#### strategy: cascade（精度優先・直列）

以下の優先順位で**最初に成功したレビュアーの結果を採用**する。
前のレビュアーが失敗（レート制限、タイムアウト等）した場合のみ次に進む。

1. **Claude Code** (`claude -p`): [references/review-prompts.md](references/review-prompts.md) の Claude 用プロンプトを使用
2. **Codex CLI** (`codex review`): [references/review-prompts.md](references/review-prompts.md) の Codex 用コマンドを使用
3. **Gemini CLI**: `${CLAUDE_SKILL_DIR}/scripts/gemini-review.sh` を実行（モデルフォールバック内蔵、プリフライトで `unavailable` なら**スキップ**）

各レビュアーの呼び出し方法とプロンプトは [references/review-prompts.md](references/review-prompts.md) を参照。

#### strategy: parallel（速度優先・並列）

Gemini と Codex を**同時に実行**し、結果をマージする。
Claude-p は Simplify と同じモデルファミリーのため parallel では使わない。

1. Gemini と Codex を並列で起動（Agent ツールで並列実行）
2. 両方の結果を統合し、重複する指摘を除去する

#### strategy: parallel-by-aspect（大規模向け・観点別並列）

大規模 diff を 1 人に全観点で見せると「広く浅く」になり失敗する。そこで
**観点をレビュアーに分担** して 3 並列で走らせる。各レビュアーは 1 観点に集中するため
プロンプトが短くなり、応答も速くなる。

##### 観点とレビュアー割り当て

| 観点 | primary | fallback (順) | プロンプト重点 |
|-----|---------|--------------|--------------|
| bug | Claude-p (`claude -p`) | Gemini → Codex | 条件分岐・境界値・エラー伝播・非同期順序 |
| security | Codex (`codex exec review`) | Claude-p → Gemini | インジェクション・認証不備・シークレット・権限昇格 |
| design | Gemini (`gemini-review.sh`) | Claude-p → Codex | 責務分離・依存方向・API 一貫性・DRY/YAGNI |

primary が失敗（タイムアウト / レート制限 / JSON パース失敗等）した場合、記載順に fallback を試す。
3 観点すべてで失敗した場合のみ「全滅」として扱う。

**プリフライトで Gemini が `unavailable` だった場合**: design 観点は最初から Claude-p を primary として使用する（Gemini を実際に起動しないことで、429 リトライの待機時間をゼロにする）。bug / security 観点の fallback から Gemini を除外して Codex に詰める。

##### 実行手順

1. **対象ファイル添付の準備（B-1: 誤検知防止）**:
   対象ファイル一覧のうち **変更行数 ≥ 50 行** のファイルを抽出し、
   `git show HEAD:<file>` で現在の全体を取得する（上限は 5 ファイルまで、
   プロンプト肥大化を防ぐため）。取得した内容を `ATTACHED_FILES` として
   各レビュアーのプロンプトに添付する。
   これにより「既に実装済みの機能を未実装と誤検知する」問題を抑止する。

2. **3 レビュアーを Agent ツールで並列起動**:
   - bug 観点: primary = Claude-p
   - security 観点: primary = Codex
   - design 観点: primary = Gemini

   呼び出し詳細は [references/review-prompts.md](references/review-prompts.md) の
   「観点別呼び出し」節を参照。各呼び出しで `REVIEW_ASPECT` を指定し、
   対応する観点別テンプレート（`review-prompt-bug.md` / `-security.md` / `-design.md`）を
   共通テンプレート（`review-prompt-template.md`）と結合してプロンプトを組み立てる。

3. **失敗時のフォールバック**:
   primary が非 0 で終了したら、fallback 順に次のレビュアーを試す。
   fallback 側も既に primary として起動中の場合は、その結果を流用する
   （同じレビュアーを同じ diff で 2 回走らせない）。

4. **結果のマージ**:
   各観点の findings に `aspect: bug|security|design` を付与して統合する。
   重複除去ルールは Step 4 を参照。

#### レビュアーが全滅した場合

全レビュアーが失敗した場合は、ユーザーに状況を報告し、Simplify の結果のみで続行するか確認する。

### Step 4: 指摘の集約（分類は行わない）

外部レビュアーが `category` フィールドを付与して返してくるので、**Opus 側では再分類しない**。
各 finding の `category`（`auto-fix` / `judgment` / `info`）をそのまま信頼してグルーピングするだけ。

この層で Opus がやるのは以下だけ:

1. 複数レビュアー（parallel / parallel-by-aspect モード）の findings をマージし、重複を除去する
   （重複判定は [references/review-prompts.md](references/review-prompts.md) の「parallel モードでの重複除去」ルールに従う）
2. `parallel-by-aspect` では、各 finding の `aspect: bug|security|design` タグを保持する。
   同一ファイル ±5 行で複数観点の指摘が重なった場合は、**severity が高いほうを採用 + aspect を配列に統合**（例: `aspect: [bug, security]`）する
3. category ごとにリスト化（`auto-fix` / `judgment` / `info`）
4. severity でソート（critical → warning → info）
5. `parallel-by-aspect` の場合、最終サマリに観点別件数（例: `bug: 3 / security: 1 / design: 5`）を出力できるよう集計する

**Opus が category を書き換えて良いケース（例外）**:
- 明らかに誤分類に見える（例: 変更不要な info が auto-fix になっている）
- severity: critical なのに info になっている
- 多数決で矛盾している（parallel で 2 レビュアーの category が割れた場合は保守側 = judgment を採用）

それ以外では findings 本文を読み直さず、カテゴリだけを見て次のステップに渡す
（これにより Opus のコンテキスト消費を大きく削減できる）。

参考: [references/classification-guide.md](references/classification-guide.md)
（こちらは外部レビュアーのプロンプト作成時の元データとして保持。通常の実行フローでは読み込み不要）

### Step 5: 修正の適用

#### 5-1. サマリ報告

まず分類結果の概要をテキストで報告する:
- auto-fix / judgment / info の件数
- 各カテゴリの主要な指摘の概要（1行ずつ）

#### 5-2. auto-fix の自動適用

auto-fix 項目を自動修正する。

#### 5-3. judgment 項目の対話的解決（一括提示）

judgment 項目は **AskUserQuestion ツールの multiQuestion 機能で 1 回の呼び出しに全件まとめて** 提示する。
1 件ずつ聞かない（往復ターンを削減するため）。

質問の書き方ルール:
- **question**: 概念的に「何が問題で、どういう選択肢があるか」を説明する。物理名（ファイル名、行番号、Step 番号等）は補足に留め、中身を詳細に把握していなくても技術的判断力で選べるレベルの抽象度にする
- **header**: 問題の概念を端的に（例: 「DB選定」「認証方式」、12文字以内）
- **option label**: 短く概念的（例: 「キャッシュ追加」「現状維持」）
- **option description**: 具体的な影響・トレードオフを補足。必要なら物理名もここに含める
- 推奨案がある場合は先頭に置き `(Recommended)` を付ける

**提示の優先度**: severity: critical の judgment を先頭に並べる。AskUserQuestion の上限を超える場合
（仕様上 5 件程度が目安）、critical を優先して含め、残りは info に格下げして最終サマリに記載する。

全件の回答を 1 度に受け取ったあと、まとめて修正を適用する。

#### 5-4. info 項目

info 項目は最終サマリに含める（対話的な確認はしない）。

### Step 6: 最終コミット（1 コミットに集約）

Step 1（Simplify）と Step 5（auto-fix + judgment 反映）の変更をまとめて 1 コミットにする:

```bash
git add <changed-files>
git commit -m "refactor: self-review (simplify + review fixes)"
```

変更が何もなかった場合はコミットを作らずにスキップし、Step 8 のサマリで報告する。

`--max-iterations >= 2` の場合は従来通りイテレーションごとに `fix: self-review iteration N - review fixes` を作成する。

### Step 7: 収束判定（デフォルトは 1 パスで完結）

**デフォルト (`--max-iterations 1`)**: Step 7 はスキップし、そのまま Step 8 へ進む。
追加レビューは作らない（コストに見合わないため）。

`--max-iterations >= 2` の場合のみ以下を評価する:

| 条件 | アクション |
|------|-----------|
| Step 1 (Simplify) で変更あり **または** Step 3 (外部レビュー) で auto-fix/judgment 指摘あり | → 次のイテレーションへ（Step 1 に戻る） |
| 両方とも変更/指摘なし | → **収束完了**、Step 8 へ |
| max-iterations に到達 | → **上限到達**、Step 8 へ（残存指摘を報告） |

### Step 7.5: 早期終了の短絡（全モードで有効）

以下の条件に 1 つでも該当したら、以降のステップをスキップして Step 8 へ直行する:

- 外部レビュー結果の findings が 0 件 かつ Simplify でも変更なし → 何もコミットせず終了
- critical が 0 件 かつ judgment が 0 件 → judgment フェーズをスキップ（auto-fix のみ適用して Step 6 へ）

### Step 8: 最終サマリ出力

[templates/review-summary.md](templates/review-summary.md) のテンプレートに基づいてサマリを出力する。

内容:
- 総イテレーション数
- 各イテレーションの概要（Simplify 変更数、レビュー指摘数、修正数）
- 使用したレビュアーと strategy
- `parallel-by-aspect` の場合は観点別件数（例: `bug: 3 / security: 1 / design: 5`）と、primary→fallback が発生したレビュアーの内訳
- 残存する info 項目（将来の改善提案）
- 終了理由（収束完了 / 上限到達）

## エラーハンドリング

| エラー | 原因 | 対応 |
|--------|------|------|
| Gemini プリフライトが unavailable | 容量不足や CLI 未応答 | Gemini を利用可能リストから除外（本番レビューでの ~70s の無駄な待機を回避）。クールダウンファイルが 15 分間保持される |
| Gemini 429 (MODEL_CAPACITY_EXHAUSTED) | サーバー容量不足 | scripts/gemini-review.sh が 1 回リトライ → モデルフォールバック → クールダウン記録 → 次のレビュアーへ |
| Codex レート制限 | 5時間ウィンドウ超過 | 次のレビュアーへフォールバック |
| Claude-p タイムアウト | ネットワークまたはAPI負荷 | 120秒タイムアウトで次のレビュアーへ |
| 全レビュアー失敗 | 全CLIが利用不可 | ユーザーに報告、Simplify 結果のみで判断を仰ぐ |
| git コミット失敗 | pre-commit hook 等 | エラー内容を表示し、ユーザーに対応を確認 |

## 注意事項

- このスキルはセッション内で Claude がオーケストレーターとして各ツールを呼び出す設計
- 外部レビュアー (`claude -p`, `codex`, `gemini`) は別プロセスとして起動される
- **デフォルトは 1 パスで完結**。重厚な反復レビューが必要な場合のみ `--deep` もしくは `--max-iterations 2+` を指定する
- judgment は **multiQuestion で一括提示** するため、中間で対話がブロックするのは最大 1 回
- コンテキストウィンドウの消費を抑えるため、`--deep` で 3 イテレーション以上続く場合は `/compact` の実行を検討する
