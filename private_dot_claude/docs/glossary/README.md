# 用語集

Claude Code が日本語で文章を書くときに引く辞書。その場しのぎの比喩を作らず、標準用語を使うために置いた。

このファイル群は常時読み込まない。原則と頻出の言い換えだけを `rules/terminology.md` に置き、そこから各ファイルを指している。

## なぜ作ったか

2026-09-11 に過去セッション 2,410 ファイルを数えた。ユーザーに伝わらなかった語の大半は、
技術用語の誤用ではなかった。Claude がその場で作った日本語の比喩だった。

| 発明された比喩 | 出現回数 | 指していたもの |
|---|---:|---|
| 司令塔 | 2,694 | 統括セッション |
| 枠 | 2,059 | 並列セッション |
| 班 | 1,188 | 担当セッション |
| 波 | 502 | 第 N 回の実施 |
| 窓 / 窓明け | 454 | 作業できる時間帯 / その終了 |

比喩が生まれる原因は、標準語を知らないことではない。その場で思い出せないことにある。
だから「使うな」と禁止せず、「代わりにこれを使う」という置き換え先を用意した。

## ファイルの構成

| ファイル | 中身 | 引く場面 |
|---|---|---|
| `jargon.md` | 内輪語 → 標準語の対応表 | 自分の言葉が比喩になっていないか確かめる |
| `design.md` | 設計・アーキテクチャ・実装品質 | 設計の話を書く |
| `infra.md` | インフラ・クラウド・IaC・運用 | AWS や Terraform の話を書く |
| `process.md` | Git・レビュー・テスト・スクラム | 開発の進め方を書く |
| `ai-agent-ops.md` | セッション運用・委譲・並列実行 | 作業の進め方を説明する（比喩が最も出やすい） |

`jargon.md` だけは `hooks/check-jargon.py`（応答の点検）と `hooks/check-question.py`（`AskUserQuestion` の質問文の点検）が機械的に読む。表の書式を崩さないこと。

## エントリの書式

分野別の 4 ファイルは 4 列の表で統一する。

| 列 | 中身 | 字数の目安 |
|---|---|---|
| 用語 | 標準用語。英語が正式なら `Idempotency（冪等性）` のように併記 | 30 字以内 |
| 意味 | 1 文で定義。言い切る | 40〜70 字 |
| 初出で添える説明 | 用語をそのまま書いたうえで、聞き慣れない読み手のために添える 1 句の説明。用語の代わりに使う言い換えではない | 20〜50 字 |
| 注意 | 誤用・混同しやすい語・使ってよい場面。無ければ `—` | 40 字以内 |

`jargon.md` は 4 列だが中身が違う（内輪語 / 検出パターン / 標準語 / 補足）。同ファイルの冒頭を読む。

## 育て方

育て方は 3 つある。

**指摘されたとき。** ユーザーが「その言葉がわからない」と言ったら、次の 3 つを行う。

1. その場で標準語に言い換えて答え直す
2. `jargon.md` に 1 行足す。検出パターンは一般語と衝突しない形にする
3. 置き換え先の標準語が分野別ファイルに無ければ、そちらにも足す

**週 1 回の見直し。** launchd の `com.h-suzuki.glossary-candidates` が毎週月曜 9:30 に `~/.local/bin/glossary-candidates` を実行し、直近 7 日の会話ログから造語の候補を `~/.claude/state/glossary-candidates.md` に書く。`glossary-research` スキルの review で候補を 1 つずつ判定し、`jargon.md` に反映する。候補ファイルは会話の断片を含むので、実機のローカルに置いたまま dotfiles には入れない。

**プロジェクトに入るとき。** その業界の用語（WordPress のサイト移行、婚活サービスの業務、名刺管理 など）を `glossary-research` スキルの research で集め、プロジェクト側の `docs/glossary/` に置く。ここにある 4 ファイルは分野をまたぐ共通語だけを持つ。

編集はソース側（`~/.local/share/chezmoi/private_dot_claude/docs/glossary/`）で行い、
`chezmoi apply` で反映する。実機側を直接編集したら `chezmoi re-add` する。

## 検出の記録を見る

`hooks/check-jargon.py` が当たった語を `~/.claude/state/jargon-hits.jsonl` に書く。
2026-09-11 は記録だけで始めた。8 日で 541 回当たり、誤検知が無かった 7 語（司令塔 / HQ / N 枠 / N 班 / レーン / 受け皿 / 検算）は 2026-09-19 に `[block]` を付けて応答を差し戻す設定に上げた。それ以外の語は記録だけを続ける。

`hooks/check-question.py` は `AskUserQuestion` の質問文を点検し、差し戻した内容を `~/.claude/state/question-lint.jsonl` に書く。こちらは検出パターンのある全行で差し戻す。質問文は書き直しの負担が小さいためである。

頻度を見るコマンド:

```bash
python3 -c "
import json,collections,pathlib
c=collections.Counter()
p=pathlib.Path.home()/'.claude/state/jargon-hits.jsonl'
for l in p.read_text().splitlines():
    for h in json.loads(l)['hits']: c[h['term']]+=h['count']
for t,n in c.most_common(): print(f'{n:5d}  {t}')
"
```

記録だけの語で誤検知が無いと分かったら、`jargon.md` の補足に `[block]` を書き足して差し戻す設定に上げる。
