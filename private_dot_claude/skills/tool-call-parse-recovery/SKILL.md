---
name: tool-call-parse-recovery
description: 「The model's tool call could not be parsed (retry also failed).」「Your tool call was malformed and could not be parsed」等の tool call パース失敗の原因分類（Case A=引数破損 / Case B=空thinking・tool_use欠落のサーバー側バグ）と、発生時・連発時の復旧手順を正本化したスキル。ユーザーがこのエラー文言を貼った／同一セッションで parse 失敗が連発した／「また malformed が出た」「ツール呼び出しが壊れる」と報告した時に必ず使用する。診断スクリプトで Case A/B を定量判定し、原因に応じた対処（hygiene 単純化 か config/セッション運用か）に振り分ける。
---

# Tool Call Parse Recovery

「tool call could not be parsed」は**同じエラー文言の裏に 2 つの別原因**がある。原因を取り違えると「対策を入れているのに直らない」が起きる。本スキルはまず原因を分類し、原因に合った対処へ振り分ける。

## 発動トリガー

以下のいずれかで必ず本スキルの手順に入る:

- ユーザーが `The model's tool call could not be parsed (retry also failed).` を貼った
- ユーザーが `Your tool call was malformed and could not be parsed` に言及した
- 同一セッションで tool call パース失敗が 2 回以上連発した
- 「また malformed が出る」「ツール呼び出しが壊れる」「対策したのに発生する」等の報告

## 2 つの原因（最重要）

| | Case A: 引数破損 | Case B: tool_use 欠落（主流） |
|---|---|---|
| 何が起きる | モデルが tool_use を出すが **JSON 引数が壊れている**（深いエスケープ、`\uXXXX` 漢字 typo、JSON-in-JSON） | `stop_reason=tool_use` なのに **tool_use ブロックが無い**。content が空 thinking のみ |
| 原因の所在 | モデルの**引数生成の出力癖**（クライアント側で観測・緩和可能） | **サーバー/ストリーミング側のバグ**。Opus 4.7(2026-05-20頃〜)/4.8 + extended thinking + 1M context で多発 |
| 緩和できるか | できる → `tool-call-hygiene.md`（引数の単純化） | **引数の書き方では緩和不可**。config/セッション運用・update・報告で対処 |
| 見分け方 | malformed 注入の直前 assistant ターンに tool_use ブロックが**有る** | 直前ターンに tool_use ブロックが**無い**（空 thinking） |

> 重要: 実測では当環境の失敗の **97% が Case B**。`tool-call-hygiene.md`（引数衛生）は Case A 専用であり、Case B には効かない。「ルールを入れているのに発生する」の正体はこれ。

## ステップ 1: 原因を分類する

診断スクリプトで Case A/B 比率を定量化する。これを飛ばして対処方針を語らない。

```bash
# 直近セッションを走査して Case A/B を分類
~/.claude/skills/tool-call-parse-recovery/scripts/diagnose-parse-errors.sh --recent 10

# いま開いているセッション単体を見る場合（$CLAUDE_CODE_SESSION_ID から特定）
f=$(ls "$HOME/.claude/projects"/*/"$CLAUDE_CODE_SESSION_ID".jsonl 2>/dev/null | head -1)
~/.claude/skills/tool-call-parse-recovery/scripts/diagnose-parse-errors.sh "$f"
```

出力の `→ 失敗の N% が Case B` で主因を判定する。

## ステップ 2: 原因別の対処

### Case B が主因（70% 以上）— サーバー側バグ

引数をどう直しても発生する。次の順で対処する:

1. **`claude update`** — 最新版を維持（v2.1.156 で Opus 4.8 thinking block 修正が入った。継続修正中）
2. **新規セッションを開始**（`--resume`/`--continue` しない）— 壊れた履歴（空 thinking ターン）が残ると同セッションで再発しやすい。長尺セッションほど顕著
3. **`/effort medium` に一時切替** — extended thinking 量を下げると空 thinking ストリーム不全が減る（推論の深さは多少落ちる、根本寄りの緩和）
4. **`/bug` で報告**（session ID 添付）— 根本はサーバー側、報告が解決を早める
5. 大規模 context 不要なら `CLAUDE_CODE_DISABLE_1M_CONTEXT=1`（1M + thinking が高リスク組合せ）

効かない対処（混同しないこと）: `/clear`（一時的）、MCP 削除、`/compact`、**引数の単純化**（＝ Case A 用なので Case B には無意味）。

### Case A が主因（30% 以下）— 引数破損

`tool-call-hygiene.md` の単純化ルールを適用する:

- 日本語を `\uXXXX` でエスケープしない（直書き）
- 構造化フィールドはオブジェクトを直接渡す（JSON-in-JSON 禁止）
- jq / クォートを単純に保つ、長い HEREDOC を避ける
- 1 メッセージ 1 ツール・重い引数を分割
- 巨大レスポンス直後は引数を素朴に

### 混在（30〜70%）

両方を併用。まず Case B 対処（update/新規セッション/effort）で土台を整え、Case A 対処（引数単純化）を重ねる。

## ステップ 3: 発生中の即応（in-session）

エラーが今まさに連発している場合、その場でできること:

1. **直近の重い操作を避ける** — 巨大ツールレスポンス（snapshot 等）直後・多段 tool chain・高 effort の長ターンが Case B の引き金になりやすい。テキストのみの短い応答や小さな `Read` を 1 つ挟んで局所的不安定を解消してから本命呼び出しに戻る
2. **同じ引数で機械リトライしない** — Case A なら単純化、Case B なら操作を分割して間を空ける
3. **連発が止まらないなら新規セッションへ退避**を提案する（Case B のとき最も確実）

## 高リスク状態の事前検出

失敗していなくても高リスクなセッションを洗い出す:

```bash
~/.claude/skills/tool-call-parse-recovery/scripts/diagnose-parse-errors.sh --risk
```

`opus-4-8 使用 + 長尺(800行以上)` のセッションを列挙する。該当セッションは resume を避け、節目で新規開始を検討する。

## 自動検出（opt-in、デフォルト OFF）

毎ターンの JSONL 解析はレイテンシ増、かつエラーは UI で既に見えるため**常時フックは入れていない**。定期ヘルスチェックしたい場合のみ、上記診断スクリプトを手動 or 任意の cron で回す。Stop フック化したい場合は `settings.json` の `hooks.Stop` に診断スクリプト（しきい値超過時のみ `notify.py` を叩くラッパ）を追加する — 採用判断はユーザーに委ねる。

## 関連

- `~/.claude/rules/tool-call-hygiene.md` — Case A（引数破損）の予防ルール正本
- `~/.claude/rules/tool-call-hygiene.md` の「失敗時のリカバリ」節から本スキルへ誘導
- GitHub Issue [#61133](https://github.com/anthropics/claude-code/issues/61133) / [#62123](https://github.com/anthropics/claude-code/issues/62123)（area:model, bug）
