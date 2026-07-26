# Tool Call Hygiene Rules

**適用範囲**: すべての tool call（Bash / Edit / Write / SendMessage / MCP 等）の引数生成と、ツール結果の報告に常時適用する。parse 失敗の原因分類・診断・復旧の詳細は `tool-call-parse-recovery` スキルが正本。

## 検証ゲート（ツール結果の捏造を防ぐ）

ツール実行の丸ごと捏造・結果の思い込みは既知の失敗様式。完了報告の前に必ず:

- **実在確認**: ファイル変更・コマンド実行を伴う作業は、完了報告の前に `git status` / 対象ファイルの Read 等で結果の実在を確認する。確認せずに「完了した」と報告しない
- **不確実性の明示**: 実行結果・事実が不確実なら「未確認」と明示する。推測を実測のように書かない。コマンド実行結果・ファイル内容は記憶を信用せず、必要なら再実行・再読込で確認する
- **根拠の引用**: 調査報告では、結論の根拠（ファイルパス・実行出力・URL）を添える

compaction 後は `hooks/postcompact-reinject.py` が同趣旨のガード（要約の記憶を信用せず再実行・再読込で確認する）を再注入する。常時ガードと矛盾させない。

## parse 失敗（malformed）の 2 原因

「tool call could not be parsed」は同じ文言の裏に 2 つの別原因がある。取り違えると「対策を入れているのに直らない」が起きる。

- **Case A（引数破損）**: tool_use は出るが JSON 引数が壊れている（深いエスケープ・`\uXXXX` 漢字 typo・JSON-in-JSON）。**下の必須ルールで緩和できる**
- **Case B（tool_use 欠落）**: `stop_reason=tool_use` なのに tool_use ブロックが無い（空 thinking のみ）。**サーバー側バグで、引数の書き方では緩和不可**

Case B の比率はモデル・環境で変わる。連発したら思い込みで語らず、`tool-call-parse-recovery` スキルの診断スクリプトで Case A/B を実測してから対処する（Case B は config/セッション運用、Case A は下記）。

## 必須ルール（Case A の予防）

1. **日本語を Unicode エスケープしない**: ❌`"データ"` → ✅`"データ"`。常に直書き
2. **構造化フィールドはオブジェクトを直接渡す（JSON-in-JSON 禁止）**: ❌`SendMessage({message: "{\"type\":...}"})` → ✅`SendMessage({message: {type: ...}})`
3. **Bash の jq / クォートを単純に保つ**: 多段パイプ・入れ子クォートを 1 行に詰めない。長い HEREDOC を避け `-m` 複数回 or ファイル経由。**command 文字列に日本語を埋めない**（`gh` の本文は `-F` / `--body-file` でファイル経由）
4. **1 メッセージ 1 ツール・引数を素朴に**: 400 行級の Write を避けセクション単位の Edit を積む。malformed が出たら引数をさらに小さく割って retry
5. **巨大レスポンスを連続させない**: snapshot 等は出力量を抑え、直後の tool call は特に素朴に。頻発したら小さな `Read` を 1 つ挟んで局所的不安定を解消してから本命へ

## codex を Bash のコマンド位置に書かない

Codex 委譲は `codex:rescue` 経由（対話は `/codex:rescue` スキル、委譲は `codex-rescue` サブエージェント）に統一する。フック `block-codex-direct.py` が deny するのは、**コマンド位置のトークンの basename が codex の実行**のみ（`codex exec` / `timeout 60 codex exec` / `FOO=1 codex` / `echo x && codex` / 絶対パス / `$(codex ...)` / バッククォート）。

フックはクォート・heredoc 本文・コメントを認識する（PR #75）ため、heredoc やクォート内に codex で始まる語・行があっても誤ブロックされない（Write ツールでファイル化して回避する必要はない）。

**例外**: レビュー系スキル同梱の `bash .../codex-review.sh` 等スクリプト呼び出しは検査対象外（basename が codex でないため）。

## 関連

- `~/.claude/skills/tool-call-parse-recovery/` — parse 失敗の原因分類・診断スクリプト・復旧手順の正本
- GitHub Issue #61133 / #62123（Case B = サーバー側バグ）
