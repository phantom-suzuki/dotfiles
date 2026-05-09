# レビュアー別プロンプト・呼び出し方法

各外部レビュアーの呼び出しコマンドとプロンプトテンプレートを定義する。

---

## 目次

1. [共通: diff の取得](#共通-diff-の取得)
2. [観点別プロンプトの組み立て](#観点別プロンプトの組み立て)
3. [観点別呼び出し（standard / deep）](#観点別呼び出しstandard--deep)
4. [Claude Code (claude -p)](#claude-code-claude--p)
5. [Claude Code (claude ultrareview)](#claude-code-claude-ultrareview)
6. [Codex CLI (codex review / codex exec)](#codex-cli-codex-review--codex-exec)
7. [Gemini CLI（`--with-gemini` 指定時のみ）](#gemini-cli--with-gemini-指定時のみ)
8. [レビュー結果の統合](#レビュー結果の統合)

---

## 共通: diff の取得

レビュー対象の diff を取得する。scope パラメータに応じて切り替える。

```bash
# changed (ベースブランチからの差分)
BASE_BRANCH=$(git merge-base HEAD main 2>/dev/null || git merge-base HEAD develop 2>/dev/null || echo "HEAD~1")
DIFF=$(git diff "$BASE_BRANCH"..HEAD)

# staged
DIFF=$(git diff --cached)

# all (全トラッキングファイルをヘッダ付きで連結)
DIFF=$(git ls-files | while read f; do echo "=== $f ==="; git show "HEAD:$f" 2>/dev/null; echo; done)
```

---

## 観点別プロンプトの組み立て

`standard` / `deep` モード（および任意のレビュアーに観点を指定する場合）では、
共通テンプレートと観点別テンプレートを結合してプロンプトを作る。

### ファイル構成

```
references/
  review-prompt-template.md   # 共通: 出力 JSON スキーマ、category 分類、共通ルール
  review-prompt-bug.md        # バグ・ロジック観点
  review-prompt-security.md   # セキュリティ観点
  review-prompt-design.md     # 設計・アーキ観点
```

共通テンプレートには 2 つのプレースホルダがある:

- `<ASPECT_FOCUS>` — 観点別テンプレートの内容を差し込む場所
- `<REVIEW_ASPECT>` — `bug` / `security` / `design` / `all` の識別子
- `<ATTACHED_FILES>` — B-1 の対象ファイル添付内容（未使用時は削除）

### 組み立てアルゴリズム（擬似コード）

```text
build_prompt(aspect, attached_files):
  common     = read("review-prompt-template.md")
  if aspect == "all":
    focus = <全観点の既存プロンプト>   # 後方互換: 現 review-prompt-template.md の「レビュー観点」章を内蔵
  else:
    focus = read(f"review-prompt-{aspect}.md")

  prompt = common
    .replace("<ASPECT_FOCUS>", focus)
    .replace("<REVIEW_ASPECT>", aspect)
    .replace("<ATTACHED_FILES>", attached_files or "（なし）")
  return prompt
```

### 対象ファイル添付（B-1、`--attach-full-file` opt-in 時のみ）

ファイル全体を外部 LLM へ送る経路は、変更行に無関係な秘密情報も同時に送信する CWE-201 系リスクがあるため、**デフォルトでは添付しない**。`--attach-full-file` を明示指定した場合のみ、以下の条件で対象ファイル全体をプロンプトに添付する:

- `standard` / `deep` モードで有効（`simple` モードは外部レビューを呼ばないため対象外）
- 対象ファイルのうち **変更行数 ≥ 50** のファイルを対象
- 添付は **最大 5 ファイル**（プロンプト肥大化防止）
- 各ファイルは `=== <path> ===\n<file content>\n` 形式で連結

```bash
# 抽出例（--attach-full-file 時のみ実行）
git diff --numstat "$BASE_BRANCH"..HEAD | \
  awk '$1 + $2 >= 50 {print $3}' | head -5 | \
  while read f; do
    echo "=== $f ==="
    git show "HEAD:$f" 2>/dev/null
    echo
  done
```

`--attach-full-file` が無い場合、誤検知の抑制は共通テンプレート（`review-prompt-template.md`）の「diff のみを見ない」節の文言（「該当ファイル全体を読んだ上で判断すること」「変更されていない行への指摘は含めない」）に委ねる。

---

## 観点別呼び出し（standard / deep）

`standard`（デフォルト）は **bug + security の 2 並列**。
`deep` または `--with-design` 指定時は **bug + security + design の 3 並列**。
Gemini は `--with-gemini` 指定時のみ経路に入る。

| 観点 | primary | fallback (順) |
|-----|---------|--------------|
| bug | Claude-p（`--ultrareview` 時は `claude ultrareview --json`） | Codex → Gemini（`--with-gemini` 時のみ） |
| security | Codex | Claude-p → Gemini（`--with-gemini` 時のみ） |
| design *(opt-in)* | Claude-p（`--with-gemini` 時は Gemini） | Codex |

### 共通: 必須フラグ（再現性確保・パース失敗根絶）

- **`claude -p`**: `--output-format json --json-schema "${CLAUDE_SKILL_DIR}/references/schemas/finding-schema.json"`
  - `ANTHROPIC_API_KEY` が設定されている環境では追加で `--bare` を付与する（hooks/skills/MCP/CLAUDE.md/auto-memory の自動ロード抑止＋起動高速化）。OAuth ログイン環境では `--bare` を付けると `Not logged in` エラーになるため、Step 0 で自動判定して `$BARE_CLAUDE` 変数経由で渡す
- **`codex exec`**: サブコマンドは `exec` を使う（`exec review` は `--output-schema` を未サポート）、`--output-schema "${CLAUDE_SKILL_DIR}/references/schemas/finding-schema.json"`、`--output-last-message <tmpfile>`、`--sandbox read-only`
  - `codex >= 0.122` 環境では `$CODEX_REPRO_FLAGS`（`--ignore-user-config --ignore-rules`）を Step 0 で組み立て済みなので追加する
  - 既知のバグ回避のため `--model gpt-5`（`gpt-5-codex` ではない）を推奨
  - レビュー指示は `--output-schema` 用プロンプト本文に「以下の diff をレビューせよ」と明示して埋め込む
- **`claude ultrareview`**: `--json` を必須化。exit code 0=完了 / 1=失敗 / 130=Ctrl-C を尊重し、stdout のみパース対象とする

### 呼び出し例（bug 観点を Claude-p に投げる、デフォルト）

```bash
ASPECT=bug
SCHEMA="${CLAUDE_SKILL_DIR}/references/schemas/finding-schema.json"
ATTACHED=$(...上記の対象ファイル添付ブロックを生成...)
PROMPT=$(build_prompt "$ASPECT" "$ATTACHED")  # 「観点別プロンプトの組み立て」節参照

echo "$DIFF" | claude -p \
  $BARE_CLAUDE \
  --model sonnet \
  --output-format json \
  --json-schema "$(cat "$SCHEMA")" \
  --permission-mode dontAsk \
  --allowedTools "Read" \
  --append-system-prompt "あなたは ${ASPECT} 観点に特化したコードレビュアーです。$PROMPT"
```

`$BARE_CLAUDE` は Step 0 で `ANTHROPIC_API_KEY` が設定済みのとき `--bare`、未設定なら空文字に設定される。
`--json-schema` は **schema ファイルの中身（JSON 文字列）** を渡すフラグであり、ファイルパスではない点に注意（`$(cat "$SCHEMA")` で展開する）。

### 呼び出し例（bug 観点を ultrareview に投げる、`--ultrareview` 時）

```bash
# 現ブランチ vs default branch を自動レビュー、JSON で出力
# 一時ファイルは mktemp で衝突回避（CWE-377/379 対策）
umask 077
TMP=$(mktemp "${TMPDIR:-/tmp}/ultrareview.XXXXXX.json")
trap 'rm -f "$TMP"' EXIT

claude ultrareview --json > "$TMP"
RC=$?
case $RC in
  0) jq '.' "$TMP" ;;        # 成功: findings を整形
  1) echo "ultrareview 失敗、claude -p にフォールバック" >&2 ;;
  130) echo "Ctrl-C 中断" >&2 ;;
esac
```

ultrareview の出力は `finding-schema.json` と完全には一致しない可能性があるため、
パース後に `aspect: bug` / `category` / `severity` を補完する正規化レイヤを通す。

### 呼び出し例（security 観点を Codex に投げる）

`codex exec review` は `--output-schema` をサポートしないため、`codex exec`（review なし）+ プロンプト埋め込みで実装する。
一時ファイルは `mktemp` で衝突回避（CWE-377/379 対策）。

```bash
ASPECT=security
SCHEMA="${CLAUDE_SKILL_DIR}/references/schemas/finding-schema.json"
ATTACHED=$(...)
PROMPT_BODY=$(build_prompt "$ASPECT" "$ATTACHED")

umask 077
TMP=$(mktemp "${TMPDIR:-/tmp}/codex-review.XXXXXX.json")
trap 'rm -f "$TMP"' EXIT

# diff をプロンプトに埋め込んで stdin で渡す
{
  echo "## 以下の diff を ${ASPECT} 観点でレビューしてください。"
  echo ""
  echo "## レビュー指示"
  echo "$PROMPT_BODY"
  echo ""
  echo "## DIFF"
  echo '```diff'
  cat -
  echo '```'
} <<< "$DIFF" | codex exec \
  --output-schema "$SCHEMA" \
  --output-last-message "$TMP" \
  --sandbox read-only \
  $CODEX_REPRO_FLAGS \
  -

cat "$TMP"
```

`$CODEX_REPRO_FLAGS` は Step 0 で `codex >= 0.122` のとき `--ignore-user-config --ignore-rules` に展開される（古い codex では空文字）。

### 呼び出し例（design 観点を Claude-p に投げる、`--with-design` 時のデフォルト）

```bash
ASPECT=design
SCHEMA="${CLAUDE_SKILL_DIR}/references/schemas/finding-schema.json"
ATTACHED=$(...)
PROMPT=$(build_prompt "$ASPECT" "$ATTACHED")
echo "$DIFF" | claude -p \
  $BARE_CLAUDE \
  --model sonnet \
  --output-format json \
  --json-schema "$(cat "$SCHEMA")" \
  --permission-mode dontAsk \
  --allowedTools "Read" \
  --append-system-prompt "$PROMPT"
```

### 呼び出し例（design 観点を Gemini に投げる、`--with-design --with-gemini` 時のみ）

```bash
REVIEW_ASPECT=design \
ATTACHED_FILES="$(...対象ファイル添付...)" \
bash "${CLAUDE_SKILL_DIR}/scripts/gemini-review.sh" <<< "$DIFF"
```

`gemini-review.sh` は環境変数 `REVIEW_ASPECT` と `ATTACHED_FILES` を読み、
内部で観点別テンプレートを結合する。未設定時は `REVIEW_ASPECT=all` として
従来どおり全観点プロンプトで動作する（後方互換）。

### Fallback の回し方

```text
for reviewer in [primary, *fallbacks]:
  if reviewer == "gemini" and not WITH_GEMINI:
    continue
  result = invoke(reviewer, aspect)
  if result.success and schema_valid(result):
    return result
return {"findings": [], "summary": f"{aspect} 観点: 全レビュアー失敗", "failed": true}
```

- 同じ diff に対して同じレビュアーを 2 回以上走らせない
  （他観点で起動済みならその結果を流用、aspect だけ書き換えて再分類はしない）
- すべての観点で失敗した場合は、SKILL.md「レビュアーが全滅した場合」に従う

---

## Claude Code (claude -p)

### 呼び出しコマンド

```bash
SCHEMA="${CLAUDE_SKILL_DIR}/references/schemas/finding-schema.json"
echo "$DIFF" | claude -p \
  $BARE_CLAUDE \
  --model sonnet \
  --output-format json \
  --json-schema "$(cat "$SCHEMA")" \
  --permission-mode dontAsk \
  --allowedTools "Read" \
  --append-system-prompt "あなたはコードレビューの専門家です。以下の diff をレビューし、JSON 形式で結果を返してください。$(cat "${CLAUDE_SKILL_DIR}/references/review-prompt-template.md")"
```

### `--bare` の取り扱い

`--bare` は hooks / skills / plugins / MCP / CLAUDE.md / auto-memory の自動探索をスキップして起動高速化＋再現性確保するフラグだが、**認証を `ANTHROPIC_API_KEY` または `--settings` 内 `apiKeyHelper` に限定** する（OAuth とキーチェーンを読まない）。

OAuth ログイン環境で `--bare` を付けると `Not logged in · Please run /login` で必ず失敗するため、Step 0 で環境変数の有無を判定して `$BARE_CLAUDE` 経由で渡す:

```bash
if [ -n "$ANTHROPIC_API_KEY" ]; then export BARE_CLAUDE="--bare"; else export BARE_CLAUDE=""; fi
```

### `--json-schema` の引数仕様

`--json-schema` は **JSON 文字列（schema 本体）** を受け取り、ファイルパスは取らない。`$(cat "$SCHEMA")` で展開して渡すこと。

### タイムアウト

120秒。超過したらフォールバック。

### エラー時

終了コード非 0、または `--json-schema` 違反で stdout が壊れた場合、次のレビュアーへフォールバック。

---

## Claude Code (claude ultrareview)

### 呼び出しコマンド

```bash
# 現ブランチ vs default branch を自動レビュー
umask 077
TMP=$(mktemp "${TMPDIR:-/tmp}/ultrareview.XXXXXX.json")
trap 'rm -f "$TMP"' EXIT
claude ultrareview --json > "$TMP"
```

PR 番号や base branch も指定可（詳細は `claude ultrareview --help`）。

### 課金

Pro/Max は **3 回無料**、それ以降は **$5–$20/run** の extra usage 課金。
このため self-review では `--ultrareview` 指定時、または `--deep` 指定時のみ起動する。

### Exit Code

| code | 意味 |
|------|------|
| 0 | 完了（findings は stdout の JSON、進捗・session URL は stderr） |
| 1 | 失敗 |
| 130 | Ctrl-C 中断 |

### エラー時

`exit 1` または schema 不整合の場合、通常の `claude -p --bare` にフォールバック。

---

## Codex CLI (codex exec)

### サブコマンド選定

`codex exec review` は `--output-schema` を **未サポート**（codex 0.111.0 で確認）。
スキーマ強制を有効にしたいので、**`codex exec`（review なし）+ プロンプト本文に「review せよ」と明示** + diff を stdin で渡す方式に統一する。

### 呼び出しコマンド（必須フラグ）

```bash
SCHEMA="${CLAUDE_SKILL_DIR}/references/schemas/finding-schema.json"
PROMPT_BODY=$(build_prompt "$ASPECT" "$ATTACHED")

umask 077
TMP=$(mktemp "${TMPDIR:-/tmp}/codex-review.XXXXXX.json")
trap 'rm -f "$TMP"' EXIT

{
  echo "## 以下の diff を ${ASPECT} 観点でレビューしてください。"
  echo ""
  echo "## レビュー指示"
  echo "$PROMPT_BODY"
  echo ""
  echo "## DIFF"
  echo '```diff'
  echo "$DIFF"
  echo '```'
} | codex exec \
  --output-schema "$SCHEMA" \
  --output-last-message "$TMP" \
  --sandbox read-only \
  $CODEX_REPRO_FLAGS \
  -

cat "$TMP"
```

`-` を末尾に置くと stdin からプロンプトを読む。

### `$CODEX_REPRO_FLAGS` の組み立て（Step 0 で実施）

```bash
if codex exec --help 2>&1 | grep -q -- "--ignore-user-config"; then
  export CODEX_REPRO_FLAGS="--ignore-user-config --ignore-rules"
else
  export CODEX_REPRO_FLAGS=""
fi
```

`--ignore-user-config` / `--ignore-rules` は `codex >= 0.122` で導入。古い codex では未対応のため空文字に倒す。

### モデル選定の注意

`gpt-5-codex` モデルは `--json` / `--output-schema` がツール起動時に無視される既知バグあり
（[openai/codex#15451](https://github.com/openai/codex/issues/15451)）。
スキーマ強制が要求される本スキルでは **`--model gpt-5`** を指定する。

### 出力フォーマット

`--output-schema` を指定しているため、Codex の出力は `finding-schema.json` に従う。
旧来の `priority`/`confidence` ベースの構造は使わず、`severity` / `category` / `aspect` を直接返させる。
Codex がスキーマに従わずに `priority` 等で返してきた場合は schema 違反としてフォールバック扱い。

### タイムアウト

180秒（Codex は Claude より応答が遅い傾向）。

### エラー時

終了コード非 0、または schema 違反の場合、次のレビュアーへフォールバック。

---

## Gemini CLI（`--with-gemini` 指定時のみ）

デフォルト経路では起動しない。`--with-gemini` が指定された場合のみ専用スクリプト経由で実行する。

### 呼び出しコマンド

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/gemini-review.sh" <<< "$DIFF"
```

スクリプトの詳細は `scripts/gemini-review.sh` を参照。リトライとモデルフォールバック（pro → flash）が内蔵。

### 出力フォーマット

スクリプトが共通 JSON フォーマットで出力する（Claude-p と同じ構造、`finding-schema.json` 準拠）。

### Gemini 固有の注意事項

- **「最初の問題で止まる」問題**: プロンプトで「全ての問題を網羅的にリストアップ」を明示指示している
- **変更していない行への提案**: プロンプトで「変更された行のみ」を明示指示している
- **MODEL_CAPACITY_EXHAUSTED**: スクリプトが gemini-2.5-pro → gemini-2.5-flash の順でフォールバック
- **プリフライト**: `--with-gemini` 指定時のみ `gemini-preflight.sh` を起動。15 分クールダウンキャッシュあり

---

## レビュー結果の統合

### 並列モードでの重複除去

複数観点（standard なら bug + security、deep / `--with-design` なら + design）の結果をマージする際、以下のルールで重複を判定する:

1. **同一ファイル + 同一行（±5行以内）+ 同一カテゴリ** → 重複とみなす
2. 重複の場合、**severity が高いほうを採用**する
3. 観点（aspect）が異なる重複は、**aspect を配列に統合**（例: `aspect: [bug, security]`）
4. レビュアー名を記録し、サマリで「どのレビュアーが指摘したか」を表示する

### simple モードでの結果処理

外部レビューを実行しないため、Simplify の結果のみ。`--force-external` で standard 相当に昇格できる。
