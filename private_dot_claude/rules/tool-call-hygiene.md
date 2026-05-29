# Tool Call Hygiene Rules

ツール呼び出しの引数生成で「malformed tool call / could not be parsed」を防ぐための規範。malformed はリポジトリ非依存の出力癖で起きるため、全プロジェクト共通ルールとして正本化する。

## スコープ — このルールは Case A 専用

「tool call could not be parsed」は**同じ文言の裏に 2 つの別原因**がある:

- **Case A（引数破損）**: モデルが tool_use を出すが JSON 引数が壊れている（深いエスケープ・`\uXXXX` 漢字 typo・JSON-in-JSON）。**クライアント側で観測・緩和でき、本ルールが対象**。
- **Case B（tool_use 欠落）**: `stop_reason=tool_use` なのに tool_use ブロックが無く content が空 thinking のみ。**サーバー/ストリーミング側のバグ**（Opus 4.7 2026-05-20 頃〜 / 4.8 + extended thinking + 1M context で多発）。**引数の書き方では緩和不可**。

> 注意: 実測では当環境の失敗の **97% が Case B**。本ルール（引数衛生）を守っても Case B は減らない。「ルールを入れているのに発生する」場合はほぼ Case B なので、`tool-call-parse-recovery` スキルの config/セッション運用対処に進むこと。原因分類は同スキルの診断スクリプトで定量判定する。

## 根本原因（Case A）

Case A の malformed はモデル側のツール引数生成（JSON 組み立て）が確率的に失敗する出力癖であり、**コンテキスト総量とは相関しない**（使用率が低くても発生する）。発生確率を高める引き金は 2 系統:

1. **エスケープの深さ**: `"` を `\"` に、日本語を `\uXXXX` に…とモデルが手で組み立てるエスケープ層が深くなると、1 文字ずれただけでパース不能になる。
2. **直前ターンの巨大テキスト**: 数百行のツールレスポンス（accessibility snapshot 等）を受けた直後は、引数生成が局所的に不安定になりやすい。これはコンテキスト総量の問題ではなく、直近ターンに巨大テキストが入ったことによる局所的な現象。（この引き金は Case B の誘発要因にもなる。）

malformed はゼロにはできない。以下のルールは Case A の確率を下げる打ち手であり、出たら単純化して再送する（「失敗時のリカバリ」参照）。

## 必須ルール

### 1. 日本語を Unicode エスケープしない

- ❌ `"reason": "データ完了"`
- ✅ `"reason": "データ完了"`

`\uXXXX` 形式は漢字 typo の温床であり、JSON エスケープを破綻させる主因。**日本語は常に直書き**する。

### 2. 構造化フィールドはオブジェクトを直接渡す（JSON-in-JSON 禁止）

ツールの引数に構造化オブジェクトを受け付けるフィールドがある場合、JSON を文字列化して渡さない。オブジェクトをそのまま渡す。

- ❌ `SendMessage({message: "{\"type\": \"shutdown_request\", \"reason\": \"...\"}"})`
- ✅ `SendMessage({message: {type: "shutdown_request", reason: "保留のため終了"}})`

文字列化した JSON（JSON-in-JSON）は、ネストしたエスケープ層が二重になり最も壊れやすい。特に `SendMessage` の `message`（shutdown_request / plan_approval_response 等）で頻発する。

### 3. Bash の jq / クォートを単純に保つ

- `gsub(...)`・入れ子クォート・パイプ多段を 1 行に詰め込まない
- 複雑な整形は複数の短いコマンドに分割するか、Read 等の専用ツールに委ねる
- 長い HEREDOC（特に commit メッセージ）を避け、`-m` を短く複数回 or ファイル経由にする
- **`command` 文字列に日本語を埋め込まない**。`echo` の進捗・確認メッセージは英語/ASCII にし、`gh` の Issue 本文・コメント・PR 本文は `-F` / `--body-file` でファイル経由にする（コマンド文字列を日本語混じりの長文にしない）。日本語が避けられないのは `gh issue create --title` 等の短い 1 行のみに留める

### 4. 1 メッセージ 1 ツール・引数を素朴に

- 重い引数（巨大 Write、長文 AskUserQuestion 選択肢）を 1 呼び出しに詰めない
- 400 行級の Write は避け、**セクション単位の小さな Edit を積み重ねる**
- malformed が出たら、引数をさらに小さく割って retry する

### 5. 巨大レスポンスを連続させない

- `take_snapshot`（chrome-devtools / playwright）等、数百行を返すツールは `depth` 制限や `filename` 保存オプションで 1 回あたりの出力量を抑える
- 同じ巨大スナップショットを毎ターン取り直さない。直前の取得結果が使えるなら再取得しない
- 巨大レスポンスの直後の tool call は特に引数を素朴に保つ。malformed が頻発したら、テキストのみの応答や小さな読み取り（`Read` 等）を 1 つ挟んで局所的な不安定を解消してから本命の呼び出しに移る

## 失敗時のリカバリ

malformed が出たら、まず**原因が Case A か Case B かを切り分ける**（同じ引数で機械的に retry しない）:

1. **Case A の疑い**（引数が深いエスケープ・JSON-in-JSON・複雑な jq 等）→ 上記 1〜4 のうち該当する書き方を**単純化して**から retry する。
2. **Case B の疑い**（単純な引数でも発生、同一セッションで連発、Opus 4.8 + 1M + high effort）→ 引数を直しても無駄。**`tool-call-parse-recovery` スキル**に進み、診断スクリプトで A/B 比率を確認し、config/セッション運用（claude update / 新規セッション / `/effort medium` / `/bug`）で対処する。

判断に迷ったら `~/.claude/skills/tool-call-parse-recovery/scripts/diagnose-parse-errors.sh --recent 10` を実行して定量判定する。

## 関連

- **`tool-call-parse-recovery` スキル** — 発生時・連発時の原因分類と復旧手順の正本（Case B 対処の本体）
- `~/.claude/CLAUDE.md` の Communication Style（日本語の orthographic correctness）
- 実プロジェクトでの malformed 多発フィードバックをもとに正本化した共通ルール
- GitHub Issue #61133 / #62123（Case B = area:model のサーバー側バグ）
