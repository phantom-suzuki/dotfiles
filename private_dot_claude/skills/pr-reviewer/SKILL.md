---
name: pr-reviewer
description: 自分にレビューリクエストが届いた PR、または番号/URL で指定された他者の PR を、状態のトリアージ → L1(Claude)+L2(Codex) の 2 段レビュー → 1 件ずつユーザー承認 → 投稿まで統率するスキル。「レビューリクエストを見て」「レビュー依頼が来てる」「PR をレビューして」「#123 #456 をレビュー」「この PR 見て」等の依頼時に必ず使用する。単一 PR でも複数 PR でも使う。peer-review スキルの上位フローで、複数 PR のトリアージ・実コード検証（worktree + Codex）・投稿判定の対話・経緯/目的/内容の要約報告を担い、レビュアーの判断コストを下げることを狙う。
---

# pr-reviewer

## このスキルの狙い

他者の PR レビューは「読む・実物と照合する・判定する・投稿する」の繰り返しで、レビュアーの認知コストが高い。このスキルは、その一連を**統率**して、ユーザー（レビュアー）が **概要レベルで把握して判定を下すだけ**の状態に持っていくことを狙う。

- **要約して噛み砕く**: 各 PR の経緯・目的・変更内容を、専門用語や番号の羅列でなく日常語で要約する。ユーザーは全 diff を読まずに判断できる。
- **実物と照合する**: ドキュメントやコードの主張がリポジトリの実体と合っているかを Codex（L2）で機械検証し、思い込みレビューを防ぐ。
- **判定を示唆する**: comment / approve / request-changes の型を提示し、理由を添える。最終判断はユーザーに委ねる。

`peer-review` スキルの単一 PR 手順（観点評価・分類・投稿形式）を土台に、複数 PR のトリアージ・環境固有の Codex 実行・投稿承認の対話を足した**上位ラッパー**。単一 PR の観点定義や分類基準の詳細は `peer-review` の references を参照してよい。

## 前提

- `gh`（GitHub CLI、認証済み）、`jq` が利用可能
- L2 に Codex を使う場合、`codex:codex-rescue` サブエージェントが使える（この環境では Codex の Bash 直叩きはフックにブロックされるため、rescue 経由が必須。詳細は [references/codex-worktree.md](references/codex-worktree.md)）
- Git リポジトリ内で実行

## 全体の流れ

```text
Step 0  レビュー対象の特定（レビューリクエスト一覧 or 指定 PR）
Step 1  各 PR のトリアージ（状態・過去レビュー・変更要求の解消確認）
Step 2  L1(Claude) + L2(Codex) レビュー … 個別 PR はサブエージェントに並列委譲
Step 3  指摘の統合・分類・判定の型づけ
Step 4  1 PR ずつ 報告 → 示唆 → 判断を仰ぐ → 投稿
Step 5  後片付け（worktree 削除）→ 最終サマリ
```

**核心**: Step 4 の「1 PR ずつユーザーの判断を仰ぐ」対話がこのスキルの中心。投稿は他者に見える取り消しにくい操作なので、一括承認を求めず、PR ごとに報告・示唆してから投稿する。並列処理が向く重い部分（各 PR の L1/L2 レビュー）だけをサブエージェントに委譲し、統率と対話はこのスキル（メイン文脈）が担う。

---

## Step 0: レビュー対象の特定

依頼の形で分岐する。

- **「レビューリクエストを見て」等、対象が明示されない場合**: 自分宛のレビューリクエストを取得する。
  ```bash
  gh search prs --review-requested=@me --state=open --json number,title,repository,updatedAt
  # 単一リポなら: gh pr list --search "review-requested:@me" --state open --json number,title,updatedAt
  ```
- **PR 番号 / URL が渡された場合**: それを対象にする（複数可）。

対象一覧をユーザーに提示してから Step 1 に進む。

## Step 1: 各 PR のトリアージ

各 PR について以下を並列取得し、**「新規レビューか / 既にレビュー済みか」**を判定する。

```bash
gh pr view <N> --json number,title,author,state,isDraft,reviewDecision,mergeStateStatus,baseRefName,headRefName,additions,deletions,changedFiles,files,body,reviews,commits,labels
gh pr diff <N>
gh pr checks <N>
gh api /repos/<owner>/<repo>/pulls/<N>/comments  # 行コメント
```

判定の要点:

- **自分（レビュアー本人）の過去レビューがあるか**で新規 / 再レビューを分ける。他者のレビューがあっても、自分が未レビューなら「新規」。
- **他レビュアーの `CHANGES_REQUESTED` が残っている場合**、それが**修正済みかを時刻の前後で確認する**。変更要求の `submittedAt` より後に対応コミットの `committedDate` があれば、指摘は解消済みで re-review 待ちの可能性が高い。この判定を誤ると「もう直っている指摘」を蒸し返してしまう。
- CI の通過状況（`gh pr checks`）、CodeRabbit のレビュー状態も拾う（最終報告に使う）。
- PR 本文から関連 Issue / Epic / ADR（`#\d+`、`.md` パス）を抽出し、必要なら `gh issue view` / Read で背景を補う。

トリアージ結果を**表**でユーザーに提示する（PR / 内容 / 自分のレビュー有無 / 他者レビュー / CodeRabbit / CI）。

## Step 2: L1(Claude) + L2(Codex) レビュー

各 PR を、設計観点の L1 と実コード観点の L2 の 2 段で見る。**個別 PR の重い評価はサブエージェントに並列委譲**し、このスキルは結果を待って統合する。

### L1（Claude・設計/整合）
`peer-review` の 5 観点（security / architecture / goal-achievement / alternatives / spec-consistency）で評価する。ドキュメント PR では architecture / goal / spec が主眼、security は該当時のみ。設計意図・Issue/ADR 整合・目的達成度を見る。実コード細部の grep 検証は L2 に委ねる。

### L2（Codex・実コード検証）
**この環境では Codex の Bash 直叩き（`codex exec` / `codex-review.sh`）はフックにブロックされる**。必ず `codex:codex-rescue` サブエージェント経由で回す。また Codex は「現在チェックアウト中のブランチと base の diff」を見るため、別ブランチで作業中だと対象 PR を解決できない。**対象 PR ブランチを `git worktree add` で取り出し、その worktree パスを rescue に渡す**。

手順の詳細（worktree 作成・codex:rescue へのプロンプト・後片付け）は [references/codex-worktree.md](references/codex-worktree.md) を参照。

L2 が見つける典型（L1 が見落としやすい）: ドキュメントの主張と実物の不一致（実在しないファイルパス・未定義の script・用語集違反）、コード変更の論理整合。今回の運用実績でも、L1 単独では approve 相当だった PR に L2 が事実誤認を複数検出した。**L2 の指摘は必ず自分でも grep/ls で裏取りしてから採用する**（Codex の指摘も間違うことがある）。

### L2 を回すか省くかの判断
L2 は実コード照合に強い一方、Codex 実行で時間・トークンが増える（実測で L1 単独の 3〜4 倍）。**常に全 PR で回すのではなく、価値が出る PR に絞る**。

- **回す**: ドキュメントが実体（ファイルパス・script 定義・用語集・設定値）を多く主張する PR / framework の境界・分類など誤りが正典に伝播する PR / コード変更の論理整合が非自明な PR
- **省いて L1 のみ**: 変更が軽微・自明、実体への言及が乏しい、Codex が使えない

省く場合は**その事実と理由をユーザーに明示**する（サイレントに 2 段構成を省かない）。

## Step 3: 指摘の統合・分類・判定

L1 と L2 の指摘を統合し、`peer-review` の分類（must-fix / should-fix / question / nit / praise）に振り分ける。同一箇所の重複は 1 件にまとめる。L1/L2 で分類が割れたら重い方を採る。

判定（comment / approve / request-changes）は機械的に決めず、**対象文書の性質**を踏まえる。判定の型と使い分けは [references/posting-norms.md](references/posting-norms.md) を参照。要点だけ再掲:

- **should-fix のみ・must-fix なし** → comment
- **notes/ ドラフト（提案中）** → approve + 「正本化までに直して」の指摘（ドラフト追加自体は通す）
- **実際に使う正本文書** → approve + 「修正したらマージ OK」の条件付き指摘
- **must-fix があっても対象がドラフト** なら approve + 指摘もありうる → **ユーザーに判断を仰ぐ**

## Step 4: 1 PR ずつ 報告 → 示唆 → 判断 → 投稿

ここがこのスキルの核心。**PR ごとに**以下を回す（まとめて承認を求めない）。

1. **経緯・目的・内容を要約**して報告する。ユーザーが概要レベルで判定できるよう、日常語で噛み砕く（[references/posting-norms.md](references/posting-norms.md) の「要約報告の指針」）。
2. **投稿ドラフト**（トップコメント + 行コメント）と、**推奨判定 + その理由**を示唆する。
3. ユーザーの判断を仰ぐ。判定変更・文面修正の指示があれば反映する。
4. 承認が出たら投稿する。投稿は **Pull Request Reviews API** でトップコメント + 行コメントをまとめて POST する（`gh pr review` は行コメント非対応）。日本語文面はファイルに書き出し `jq --rawfile` で JSON を組み立てる（投稿レシピは [references/posting-norms.md](references/posting-norms.md)）。

投稿文面は**投稿規範**（他レビュアーの既出指摘とその派生は除く / 感謝の枕詞を使わない / やさしい日本語 / 番号や記号だけで語らない）に従う。詳細は [references/posting-norms.md](references/posting-norms.md)。

## Step 5: 後片付け・最終サマリ

- Step 2 で作った worktree を削除する（`git worktree remove --force` → `git worktree prune`）。
- 全 PR の投稿結果を**表**でまとめる（PR / 判定 / 投稿リンク / 他者レビュー / CodeRabbit / CI）。CI・CodeRabbit の通過状況、残っている変更要求（re-review 待ち等）も添える。

---

## 将来拡張: 自分の PR のマージ判断統率

このスキルは「他者の PR をレビューする（reviewer）」が主だが、いずれ「**自分の PR をマージしてよいか**の判断統率（reviewee 側）」も担えると価値が高い。その場合は観点が変わる（受けたレビューコメントの解消確認・CI/承認ゲートの充足・マージ方針の確認）。マージの実行はユーザーの明示指示がある時のみ（`git-safety.md` の PR Merge Policy 厳守）。実装するなら別モードとして分岐させ、reviewer フローと混ぜない。

## 関連

- `peer-review` スキル（単一 PR の観点定義・分類基準・投稿形式の土台）
- `coderabbit-approve` スキル（CodeRabbit の正式 APPROVED を得る運用）
- `~/.claude/rules/git-safety.md`（投稿・マージの安全原則）
