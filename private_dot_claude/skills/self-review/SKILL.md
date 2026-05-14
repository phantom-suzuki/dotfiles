---
description: >-
  Claude Code 内蔵 /simplify と外部レビュアー（Claude-p + Codex）を組み合わせた
  軽量セルフレビュースキル。デフォルトは bug + security の 2 観点 / 2 並列で 1 パス完結。
  design 観点・Gemini・claude ultrareview はすべて opt-in。判断が必要な項目は開発者に確認する。
  「セルフレビュー」「レビュー回して」「self-review」等の依頼時に使用。
argument-hint: "[--strategy auto|simple|standard|deep] [--scope changed|staged|all] [--max-iterations N] [--skip-simplify] [--skip-external] [--simplify-via internal|codex] [--with-design] [--with-gemini] [--ultrareview] [--attach-full-file] [--force-external] [--deep]"
---

# Skill: /self-review

## 概要

Claude Code 内蔵 `/simplify` と外部レビュアーを組み合わせ、**1 パス（既定）** で完結する軽量セルフレビュースキル。
所要時間とセッション消費を抑えることを最優先する。重厚な反復レビューは `--deep` で明示的に切り替える。

**デフォルト動作（`standard` strategy）**:
- 1 イテレーションで完結（内蔵 `/simplify` → bug + security の 2 並列レビュー → 修正適用 → 1 コミット）
- 観点は **bug（Claude-p）+ security（Codex）の 2 軸固定**。design・Gemini・ultrareview は明示 opt-in
- 全 CLI 呼び出しに `--bare` / `--output-schema` / `--ignore-user-config` 等の **再現性確保フラグを必須化**
- judgment 項目は **AskUserQuestion の multiQuestion で最大 3 件まで一括提示**、4 件目以降は info 格下げ
- 中間コミットは作らず、最後に 1 コミットだけ作成

**軽量経路（`simple` strategy、自動判定）**:
- diff ≤ 30 行 かつ ファイル ≤ 3 の小規模変更では Simplify のみを実行し、外部レビューを自動スキップ
- 強制起動したい場合は `--force-external` を指定

**重厚経路（`deep` strategy、明示）**:
- `--deep` 指定時に standard を superset：design 観点 + ultrareview を自動有効化、`--max-iterations 3` まで拡張

## パラメータ

| パラメータ | デフォルト | 説明 |
|-----------|----------|------|
| `--strategy` | `auto` | `auto`（diff 規模で simple/standard を自動判定）/ `simple`（Simplify のみ）/ `standard`（bug + security 並列）/ `deep`（design + ultrareview 込み） |
| `--scope` | `changed` | `changed`（ベースブランチからの差分）/ `staged`（ステージ済み）/ `all`（全ファイル） |
| `--max-iterations` | 1（`--deep` 時は 3） | 最大ループ回数。通常は 1 パスで十分 |
| `--skip-simplify` | false | Simplify をスキップ |
| `--skip-external` | false | 外部レビューをスキップ（Simplify のみ実行） |
| `--simplify-via` | `internal` | `internal`（Opus 自身の `/simplify`）/ `codex`（codex exec に委譲、レート消費に注意） |
| `--with-design` | false | design 観点を追加（claude -p または `--with-gemini` 時は Gemini） |
| `--with-gemini` | false | Gemini を opt-in。プリフライトが起動するのもこの指定時のみ |
| `--ultrareview` | false | bug の primary を `claude ultrareview --json` に置換（課金あり: Pro/Max は 3 回無料、以降 $5–$20/run） |
| `--attach-full-file` | false | 変更行 ≥ 50 のファイル全体を外部 LLM に添付（誤検知抑制目的）。**デフォルトでは添付しない**（CWE-201 機密漏洩リスク回避）。明示 opt-in 時のみ有効 |
| `--force-external` | false | 自動スキップ閾値を無視して外部レビューを強制実行 |
| `--deep` | false | 重厚モード: `--strategy deep --max-iterations 3 --with-design --ultrareview` を自動適用 |

## 前提条件

- Git リポジトリ内で実行すること
- 以下の CLI が利用可能であること（なければ自動スキップまたはフォールバック）:
  - `claude` (Claude Code、`-p --bare` モードで外部レビュアーとして使用、`ultrareview` も)
  - `codex` (Codex CLI、外部レビュアー兼 `--simplify-via=codex` の委譲先)
  - `gemini` (Gemini CLI、`--with-gemini` 時のみ起動)
  - `jq` (JSON パースに使用)

## 実行手順

### Step 0: 初期化

1. Git リポジトリであることを確認する:
   ```bash
   git rev-parse --git-dir >/dev/null 2>&1 || { echo "Git リポジトリ内で実行してください"; exit; }
   ```
2. パラメータを解析する（未指定はデフォルト値）。`--deep` 指定時は内部的に
   `--strategy deep --max-iterations 3 --with-design --ultrareview` を強制する
3. 利用可能なレビュアーと環境を検出する:
   ```bash
   command -v claude && echo "claude: bin found"
   command -v codex && echo "codex: bin found"
   [[ "$WITH_GEMINI" == "true" ]] && command -v gemini && echo "gemini: bin found"

   # claude -p の --bare 可否判定（OAuth ログイン環境では --bare は使えない）
   if [ -n "$ANTHROPIC_API_KEY" ]; then export BARE_CLAUDE="--bare"; else export BARE_CLAUDE=""; fi

   # codex の --ignore-user-config / --ignore-rules 可否判定
   if codex exec --help 2>&1 | grep -q -- "--ignore-user-config"; then
     export CODEX_REPRO_FLAGS="--ignore-user-config --ignore-rules"
   else
     export CODEX_REPRO_FLAGS=""
   fi
   ```

3.5. **Gemini プリフライト（`--with-gemini` 指定時のみ）**:
   `--with-gemini` が無ければプリフライト自体を実行せず、Gemini を完全に経路から外す。
   指定時のみ軽量プローブで実際に応答するかを先に確認する（容量不足 429 頻発時に本番レビューで最大 ~70s 浪費するのを避けるため）。
   ```bash
   if [[ "$WITH_GEMINI" == "true" ]]; then
     export GEMINI_STATUS=$(bash "${CLAUDE_SKILL_DIR}/scripts/gemini-preflight.sh" 2>/dev/null || echo "unavailable")
   else
     export GEMINI_STATUS="disabled"
   fi
   ```
   結果の扱い:
   - `disabled` → Gemini を呼ばない（デフォルト経路）
   - `available` → Gemini を通常通り使用（pro → flash フォールバック）
   - `flash-only` → pro はスキップし flash のみで動作
   - `unavailable` → 1 回だけプローブ失敗、以降は Gemini をスキップ

   **クールダウン**: 過去 15 分以内に 429 を検知した場合、プリフライトはプローブを省略して
   即 `unavailable` を返す（`~/.claude/skills/self-review/.gemini-cooldown` の mtime で判定）。
4. `--scope` に応じて対象ファイルを特定する:
   - `changed`: `git diff --name-only $(git merge-base HEAD main)..HEAD` （main がなければ develop を試行）
   - `staged`: `git diff --cached --name-only`
   - `all`: 全トラッキングファイル
5. 対象ファイルがなければ「レビュー対象がありません」と報告して終了
6. `--strategy auto` の場合、diff 規模と opt-in フラグで戦略を決定する:
   - **`--deep` 指定時**: `deep` を強制
   - **diff 行数 ≤ 30 かつ ファイル数 ≤ 3 かつ `--force-external` なし**: `simple`（Simplify のみ、外部レビュー自動スキップ）
   - **それ以外**: `standard`（bug + security の 2 並列）
   - **明示指定**（`--strategy simple|standard|deep`）はそのまま尊重し閾値判定を上書き
7. `classification-guide.md` は通常 **読み込まない**（分類は外部レビュアー側で済ませているため）。
   明らかな誤分類が多発する場合のみ [references/classification-guide.md](references/classification-guide.md) を読み込んで手動補正する
8. 初期状態をユーザーに報告する:
   - 対象ファイル一覧（規模が大きければ件数のみ）
   - 選択された strategy
   - 有効化された opt-in フラグ（`--with-design` / `--with-gemini` / `--ultrareview` / `--simplify-via=codex`）
   - 利用可能なレビュアー
   - max-iterations

### Step 1: Simplify 実行（原則 Claude Code 内蔵 `/simplify`）

`--skip-simplify` でなければ Simplify を実行する。

**原則: Opus 自身が Claude Code 内蔵 `/simplify` スキルを起動する**。Codex 委譲は
レート消費が大きいため `--simplify-via=codex` 指定時のみの opt-in に降格した。

#### 1-1. 内蔵 `/simplify` で実行（デフォルト経路）

Opus が対象ファイル群に対して `/simplify` を起動し、再利用性チェック・複雑さ除去・効率性改善を行う。
`/simplify` の進行中は git に触れないこと（最終コミットは Step 6 で 1 回にまとめる）。

#### 1-2. Codex に委譲する場合（`--simplify-via=codex` 指定時のみ）

Codex CLI に委譲する（再現性確保のため設定を無視）:

```bash
cd <repo-root> && codex exec \
  --full-auto \
  --sandbox workspace-write \
  --ignore-user-config \
  --ignore-rules \
  "$(cat <<'EOF'
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

完了後、Opus は `git diff --stat` で差分の規模だけ確認する（diff 本体を全件精読はしない）。
Codex 委譲が失敗した場合は内蔵 `/simplify` にフォールバックし、ユーザーに失敗を 1 行で報告する。

#### 1-3. 結果の記録

どちらの経路でも、変更があったファイルの一覧だけを記録しておく（Step 6 のコミット対象になる）。

### Step 2: Simplify 結果の記録（コミットはしない）

Step 1 で変更があった場合、**stash や中間コミットを作らずそのまま Step 3 に進む**。
中間コミットは廃止した（理由: squash 前提で無駄な履歴が増え、rebase も煩雑になるため）。
最終コミットは Step 6 で一括作成する。

`--max-iterations >= 2` の場合のみ、イテレーション境界を明示する目的で中間コミット
（`refactor: self-review iteration N - simplify`）を作成する。

### Step 3: 外部レビュー実行

`--skip-external` または `simple` strategy（`--force-external` 無し）の場合はこの Step を丸ごとスキップ。
それ以外は strategy に応じて以下を実行する。

#### 共通: 対象ファイル添付（B-1: 誤検知防止、`--attach-full-file` opt-in）

`--attach-full-file` が指定された場合のみ、対象ファイル一覧のうち **変更行数 ≥ 50 行** のファイルを最大 5 件抽出し、
`git show HEAD:<file>` で全体を取得して `ATTACHED_FILES` としてプロンプトに添付する。
「既に実装済みの機能を未実装と誤検知する」問題を抑止する。

**デフォルトで添付しない理由**: 全文添付は変更行に無関係な秘密情報（API キー、個人情報、内部設定）を外部 LLM へ送る経路となり、CWE-201（Insertion of Sensitive Information Into Sent Data）に該当するリスクがある（self-review skill 自身の内部レビューで検知された設計上の問題）。
誤検知の抑制はプロンプト側の文言（`review-prompt-template.md` の「diff のみを見ない」節）で代替する。

#### 共通: CLI フラグの必須化

すべての外部レビュアー呼び出しで以下を必須とする（再現性確保・パース失敗根絶のため）:

| CLI | 必須フラグ |
|-----|----------|
| `claude -p` | `--output-format json --json-schema "$(cat ${CLAUDE_SKILL_DIR}/references/schemas/finding-schema.json)"`（フラグ引数は **JSON 文字列**、ファイルパスではない）、`--permission-mode dontAsk`、`--allowedTools "Read"`。`ANTHROPIC_API_KEY` 設定時のみ追加で `--bare`（OAuth ログイン環境では `--bare` を付けると認証エラー `Not logged in` になるため Step 0 で自動判定） |
| `codex exec` | サブコマンドは **`exec`**（`exec review` は `--output-schema` 非対応のため使わない。レビュー指示はプロンプト本文に埋め込む）、`--output-schema "${CLAUDE_SKILL_DIR}/references/schemas/finding-schema.json"`、`--output-last-message <tmpfile>`、`--sandbox read-only`。`codex >= 0.122` の環境では `--ignore-user-config` / `--ignore-rules` も付与（古いバージョンでは省略） |
| `claude ultrareview` | `--json`（exit code 0=完了/1=失敗/130=Ctrl-C を尊重）。Pro/Max は無料枠 3 回、以降は課金 |

呼び出し例とプロンプト詳細は [references/review-prompts.md](references/review-prompts.md) を参照。

#### strategy: standard（デフォルト・bug + security の 2 並列）

| 観点 | primary | fallback (順) | プロンプト |
|-----|---------|--------------|----------|
| bug | `claude -p --bare ...`（`--ultrareview` 時は `claude ultrareview --json`） | Codex → Gemini（`--with-gemini` 時のみ） | `review-prompt-bug.md` |
| security | `codex exec ...` | Claude-p（`--bare`） → Gemini（`--with-gemini` 時のみ） | `review-prompt-security.md` |

実行:

1. bug と security を Agent ツールで **並列起動**（2 並列）
2. primary が失敗（非 0 終了 / JSON Schema 違反 / タイムアウト）したら fallback 順に次を試行
3. 同じレビュアーを同じ diff で 2 回走らせない（既に他観点で起動中ならその結果を流用）
4. 結果に `aspect: bug` / `aspect: security` を付与して統合

#### strategy: deep（重厚モード・3 並列 + ultrareview）

`--deep` 指定時、または `--strategy deep` 明示時。standard を superset し、design 観点を追加する:

| 観点 | primary | fallback (順) | プロンプト |
|-----|---------|--------------|----------|
| bug | `claude ultrareview --json` | `claude -p --bare ...` → Codex | `review-prompt-bug.md` |
| security | `codex exec ...` | Claude-p → Gemini（`--with-gemini` 時） | `review-prompt-security.md` |
| design | `claude -p --bare ...`（`--with-gemini` 時は Gemini） | Codex | `review-prompt-design.md` |

`--with-gemini` が無い場合、Gemini 経路は完全に外す（`gemini-preflight.sh` も呼ばない）。

#### `--with-design` 単独指定（standard + design）

`--deep` 無し で `--with-design` のみ指定された場合、standard の 2 並列に design 観点を加えて 3 並列で起動する。
ultrareview は明示的に `--ultrareview` を付けない限り起動しない。

#### レビュアーが全滅した場合

全観点で失敗したら、ユーザーに状況を報告し、Simplify の結果のみで続行するか確認する。

### Step 4: 指摘の集約（分類は行わない）

外部レビュアーが `category` フィールドを付与して返してくるので、**Opus 側では再分類しない**。
各 finding の `category`（`auto-fix` / `judgment` / `info`）をそのまま信頼してグルーピングするだけ。

この層で Opus がやるのは以下だけ:

1. 複数観点の findings をマージし、重複を除去する
   （重複判定は [references/review-prompts.md](references/review-prompts.md) の「並列モードでの重複除去」ルールに従う）
2. 各 finding の `aspect: bug|security|design` タグを保持する。
   同一ファイル ±5 行で複数観点の指摘が重なった場合は、**severity が高いほうを採用 + aspect を配列に統合**（例: `aspect: [bug, security]`）する
3. category ごとにリスト化（`auto-fix` / `judgment` / `info`）
4. severity でソート（critical → warning → info）
5. 最終サマリに観点別件数（例: `bug: 3 / security: 1` または deep 時 `bug: 3 / security: 1 / design: 2`）を出力できるよう集計する

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

**提示の優先度・上限**: AskUserQuestion multi の上限を **3 件に固定** する（往復ターン抑制と判断疲れ防止のため）。
severity: critical の judgment を先頭に並べ、3 件を超えたら 4 件目以降は info に格下げして最終サマリに記載する。
critical が 3 件以上ある異常時のみ、AskUserQuestion を 2 回に分けて出すことを許容する。

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

- **`simple` strategy**（diff ≤ 30 行 かつ ファイル ≤ 3、`--force-external` なし）→ Step 3 を全スキップし、Simplify 結果のみで Step 6 → Step 8 へ
- 外部レビュー結果の findings が 0 件 かつ Simplify でも変更なし → 何もコミットせず終了
- critical が 0 件 かつ judgment が 0 件 → judgment フェーズをスキップ（auto-fix のみ適用して Step 6 へ）

### Step 8: 最終サマリ出力

[templates/review-summary.md](templates/review-summary.md) のテンプレートに基づいてサマリを出力する。

内容:
- 総イテレーション数
- 各イテレーションの概要（Simplify 変更数、レビュー指摘数、修正数）
- 使用した strategy（simple/standard/deep）と有効な opt-in フラグ
- 観点別件数（例: standard なら `bug: 3 / security: 1`、deep / `--with-design` なら `bug: 3 / security: 1 / design: 2`）
- primary → fallback が発生したレビュアーの内訳
- judgment が 4 件以上発生して info に格下げされた件数（あれば）
- 残存する info 項目（将来の改善提案）
- 終了理由（収束完了 / 上限到達 / simple 早期終了）

## エラーハンドリング

| エラー | 原因 | 対応 |
|--------|------|------|
| Gemini プリフライトが unavailable | `--with-gemini` 指定下で容量不足や CLI 未応答 | Gemini を利用可能リストから除外し、クールダウンを 15 分保持。自動で Codex フォールバックは行わないため、必要なら `--with-gemini` を外して再実行する |
| Gemini 429 (MODEL_CAPACITY_EXHAUSTED) | サーバー容量不足 | scripts/gemini-review.sh が 1 回リトライ → モデルフォールバック → クールダウン記録し、`[self-review] gemini unavailable...` を返して終了。呼び出し側は `--with-gemini` を外すか手動続行で対応する |
| Codex レート制限 | 5時間ウィンドウ超過 | 次のレビュアー (Claude-p) へフォールバック。Simplify を Codex に委譲する `--simplify-via=codex` は特にレートを食う |
| Codex `--output-schema` 違反 | gpt-5-codex モデルでツール起動時に schema が無視される既知バグ | `gpt-5` モデル指定 / `--output-last-message` の組合せで回避。Schema 違反検出時は Claude-p フォールバック |
| Claude-p タイムアウト | ネットワークまたはAPI負荷 | 120秒タイムアウトで次のレビュアーへ |
| ultrareview 失敗 (`exit 1`) | 課金枠超過 / API 障害 | 通常の `claude -p --bare` にフォールバック |
| 全レビュアー失敗 | 全CLIが利用不可 | ユーザーに報告、Simplify 結果のみで判断を仰ぐ |
| git コミット失敗 | pre-commit hook 等 | エラー内容を表示し、ユーザーに対応を確認 |

## 注意事項

- このスキルはセッション内で Claude がオーケストレーターとして各ツールを呼び出す設計
- 外部レビュアー (`claude -p`, `codex`, `gemini`, `claude ultrareview`) は別プロセスとして起動される
- **デフォルトは 1 パスで完結 / bug + security の 2 軸**。`--with-design` / `--with-gemini` / `--ultrareview` / `--deep` はすべて opt-in
- 課金が発生する `--ultrareview`（Pro/Max は無料枠 3 回）は明示的に必要な PR でのみ使う
- judgment は **multiQuestion で最大 3 件まで一括提示**。4 件目以降は info に格下げするため、判断疲れにくい
- コンテキストウィンドウの消費を抑えるため、`--deep` で 3 イテレーション以上続く場合は `/compact` の実行を検討する
