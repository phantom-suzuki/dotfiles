---
name: skill-improve
description: 直近セッションの会話ログ（jsonl）から「詰まり・ユーザー修正指示・parse 失敗・レビュー指摘」を signal として抽出し、原因となったスキル/ルールの改善案を提示して、人間承認のうえ chezmoi ソースへ反映する自己改善ループ（MVP・手動実行）。「スキル改善」「振り返って改善」「self-improve」「スキルを直したい」「今のやりとりから学んで」等の依頼時に使用。
disable-model-invocation: true
argument-hint: "[session-id | latest]"
---

# Skill Improve — Self-Improving Loop (MVP)

スキルや rules を「使う中で見つかった失敗」から継続的に改善するためのループ。本スキルは手動トリガーの MVP 版で、**signal の抽出 → 原因スキルへの紐付け → 改善案の提示 → 人間承認 → 反映 → ログ蓄積** を 1 パスで回す。

参考設計: <https://zenn.dev/sonicgarden/articles/claude-code-self-improving-loop>（本 MVP は同記事の Discovery + Triage 部分のみを手動で実装し、Routines 無人運転・GitHub Issue 化・多段品質ゲートは「将来拡張」に回している）。

## 安全原則（必守）

- **スキル/ルールを自動で書き換えない**。改善案は必ず提示し、ユーザーが accept した項目のみ反映する。
- **編集は chezmoi ソース側**（`~/.local/share/chezmoi/private_dot_claude/skills/` または `.../rules/`）に対して行う。ターゲット（`~/.claude/...`）を直接編集しない。反映は `chezmoi apply`、commit/push はユーザー判断（`git-safety.md`）。
- **jsonl は読み取りのみ**。巨大なので jq で必要フィールドだけ抽出し、全文をダンプしない（`tool-call-hygiene` 準拠）。
- **改善ログに生の会話を貼らない**。`improvement-log.md` は chezmoi ソース配下 = public リポジトリ（`github.com/phantom-suzuki/dotfiles`）へ push されうる。signal は抽象化した要約のみ記録し、ユーザー発言の生断片・パス・トークン・個人情報など機微なものを含めない。判断に迷う内容は記録せず提示に留める。
- scrum イベントの自発提案はしない（[[feedback-no-scrum-event-suggestion]]）。

## Procedure

### Step 1: 対象セッションの特定

引数なし or `latest` なら最新の jsonl を対象にする。`<session-id>` 指定ならそれを使う。

```bash
PROJECT_KEY=$(pwd | sed 's|[/.]|-|g')   # 例: /Users/h-suzuki/.claude -> -Users-h-suzuki--claude
DIR="$HOME/.claude/projects/${PROJECT_KEY}"
SESSION=$(ls -t "$DIR"/*.jsonl | head -1)   # latest の場合
echo "target: $SESSION"
```

### Step 2: signal の抽出

**実ユーザー入力だけ**を抽出する。スキル注入本文（`<command-name>` 等で差し込まれる SKILL.md 全文）・ルール本文・ファイル内容は signal ではない。これらを拾うと誤検出する（実測: スキル定義内の例示文言や、parse 失敗を話題にした発言まで拾った）。

```bash
# 実ユーザー入力のみ抽出（meta・スキル注入・貼り付けられたスキル本文を除外）
jq -r 'select(.type=="user" and (.isMeta != true))
  | (if (.message.content|type)=="string" then .message.content
     else (.message.content[]? | select(.type=="text") | .text) end)
  | select(test("<command-name>|<command-message>|Base directory for this skill")|not)' "$SESSION" \
  | grep -v '^$'
```

下の「signal カタログ」のパターンに該当する箇所を拾う。**grep ヒットがスキル定義・ルールの例示文言（例: `communication-style.md` の不満サイン語リスト）でないかは必ず目視確認する。**

parse 失敗は **grep のカウントを signal にしない**。`grep -c "malformed..."` はドキュメント本文やその語に触れた発言まで数え過大になる（実測: 実エラー 0 件を 12 件と誤カウント）。実際に parse 失敗が起きたかは「同一ツール呼び出しの連続 retry」「ユーザーが malformed を報告」で裏取りし、裏が取れなければ signal にしない:

```bash
# 参考カウント（過大なので、これ自体は signal にしない・裏取り前提）
grep -E -c -i "malformed and could not be parsed|tool call could not be parsed" "$SESSION"  # -E で BSD/GNU 両対応
```

### Step 3: 原因スキル/ルールへの紐付け

抽出した各 signal について「どのスキル・rule・既定挙動が原因か」を推定して紐付ける。直前後の文脈（どのスキル実行中だったか、どのツールを呼んでいたか）を jsonl の前後行から読む。原因スキルが特定できないものは「新規ルール/スキルの候補」として扱う。

### Step 4: 改善案の提示

signal を優先度順（再発頻度 × 影響度）に並べ、各々について **具体的な diff 案** を提示する:

- 対象ファイル（chezmoi ソースパス）
- 直す箇所と、before → after の案
- その変更でどの signal の再発を防げるか（根拠を 1 行）

該当スキルが無い場合は、新規スキル追加 or 既存 rule への追記を提案する。

> 提示は `communication-style.md` の「報告・回答の型」に従い、結論（何を直すか）を先に出し、比較が要るときは案を表で出す。長い本文をターミナルにベタ書きしない。

### Step 5: 人間承認

改善案を番号付きで提示し、accept する項目をユーザーに選んでもらう。accept された項目のみ次へ進む。reject 理由があれば改善ログに残す（次回同じ提案を繰り返さないため）。

### Step 6: 反映（chezmoi ソース）

accept された改善を chezmoi ソース側に Edit で反映する。

```bash
# 反映後に差分確認をユーザーへ促す（apply は内容確認後）
chezmoi diff
chezmoi apply   # ユーザー確認後
```

- SKILL.md / rules の `.md` は tmpl ではないので直接編集してよい。
- `settings.json` 等の tmpl 管理ファイルを触る場合は CLAUDE.md の「tmpl の落とし穴」に従う。
- commit/push はユーザーが判断（`chezmoi cd` → commit）。

### Step 7: 改善ログの蓄積

反映した改善（と reject した提案＋理由）を `docs/improvement-log.md` に追記して蓄積する。蓄積先はソース側:
`~/.local/share/chezmoi/private_dot_claude/skills/skill-improve/docs/improvement-log.md`

1 エントリの形式（日付は会話の currentDate を使う。`date` コマンドの結果に依存しない）:

```markdown
## <YYYY-MM-DD> session <session-id 先頭8桁>
- signal: <検出した失敗の要約>
- 原因: <紐付けたスキル/rule>
- 対応: <accept して反映した変更 / reject＋理由>
```

## signal カタログ（検出パターン）

| signal 種別 | 検出の手がかり | 典型的な改善先 |
|---|---|---|
| ユーザー修正・否定 | 「いえ」「ちがう/違う」「そうじゃない」「ではなく」「やり直し」「論点」「同じ話」「おちょくって」「わからない」「冗長」「長い」 | 該当スキルの手順・`communication-style.md` |
| 同一/類似指示の繰り返し | ユーザーが同じ要求を 2 回以上言っている | スキルが指示を取りこぼす箇所 |
| tool call parse 失敗の頻発 | "malformed and could not be parsed" 等 | `tool-call-hygiene` / `tool-call-parse-recovery` |
| レビュースキルの指摘 | self-review / peer-review が挙げた finding | 指摘対象のスキル/コード規約 |
| 手戻り・方針転換 | 「やっぱり」「方針変更」「戻して」 | 着手前確認が足りないスキル |

> サインは `communication-style.md` の「不満サイン検知時のリカバリ」の語彙と意図的に揃えている（旧 `explain-discipline` スキルから 2026-07-17 に統合）。同ルールがリアルタイムのリカバリを担い、本スキルは「サインを後から集約して恒久対策に変える」役割。

## 将来拡張（MVP では未実装）

記事の中〜フル段階に相当する以下は、MVP が落ち着いてから検討する:

- 改善点の **GitHub Issue 化** と accept/reject 追跡
- **Routines による毎日の無人 triage** 実行（人間は最終 PR レビュー・マージのみ）
- **多段品質ゲート**（verify-diff / skill-review / publicity-review）＋外側ループ
- 対話用スキルと無人 triage 用スキルの分離

## 関連

- `~/.claude/rules/communication-style.md`（不満サイン検知時のリアルタイム対処。旧 `explain-discipline` スキルを統合。本スキルは事後集約）
- `~/.claude/rules/tool-call-hygiene.md` / `~/.claude/skills/tool-call-parse-recovery/`（parse 失敗 signal の対処）
- `~/.claude/skills/self-review/`（finding を signal 源として利用）
- `~/.claude/CLAUDE.md` の chezmoi 編集ワークフロー（反映先の制約）
