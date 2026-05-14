# 投稿ガイド

peer-review のコメント投稿に関する文体・判定・対話フローのルール。

---

## 文体

### 基本

- **日本語、敬体**（敬語）
- レビュアー・作成者ともに日本語ネイティブの前提
- 英語で書く場合は、ユーザーが明示的に指定したときのみ
- github-conventions.md に準拠

### トーン

- **コラボレーティブ**: 「〜すべき」ではなく「〜していただけると」「〜が良いと考えます」
- **根拠を示す**: 「これは悪い」ではなく「〜の理由で、こういう影響がある」
- **作成者の裁量を尊重**: 「強制」より「確認」「推奨」
- **praise から始める**: 否定から入らず、良かった点を最初に提示

### 避けるべき表現

- ❌ 「〜は間違っています」「〜が悪い」
- ❌ 「なぜこんな設計にしたの？」（詰問口調）
- ❌ 「〜すべき」の連発（強制的)
- ⭕ 「〜していただけると助かります」
- ⭕ 「〜の可能性がありますが、いかがでしょうか」
- ⭕ 「〜が良いと考えますが、ご判断お任せします」

---

## 判定の選び方

### approve

- 指摘なし or praise のみ
- should-fix レベルが数件あっても、「本 PR はこのままで問題ない」と判断した場合
- 作成者とのレビュー往復を避けたい場合

### comment（デフォルト推奨）

- must-fix 1〜2 件 かつ 文言修正レベル
- should-fix 多数だが後続 Issue で吸収可
- 作成者の判断に委ねたい場合
- **日本語組織文化ではこれが最も使いやすい**

### request-changes（慎重に）

- 本番影響のあるセキュリティ問題
- ADR / 重要規約の明確な違反
- 設計の根本を揺るがす不整合
- 作成者に「修正するまでマージしない」という強い意思表示が必要な場合

### 選択の指針

```
指摘なし？
├─ Yes → approve
└─ No → 継続

must-fix はある？
├─ No → comment（should-fix 中心なら）
└─ Yes → 継続

must-fix は設計の根本？
├─ Yes → request-changes
└─ No（文言 / 確認レベル）→ comment（推奨）
```

---

## 行コメント vs トップコメント

### 原則: 指摘ごとに行コメントへ分離（CodeRabbit 形式）

- 各指摘が該当行にピン留めされるため、作成者が返信・対応の粒度を揃えやすい
- GitHub UI で指摘ごとの「Resolve conversation」が使え、対応状況の可視化がしやすい
- 1 本の長大トップコメントは読みづらく、返信も集約されて対応状態が追えなくなる

### トップコメントに置く情報

- 冒頭の謝意・総評（2-3 文）
- 良かった点（praise 列挙）
- **指摘サマリ**（件数 + 簡易タイトルのみ、詳細は「行コメントへ」と誘導）
- 総評（判定理由）
- レビュー方法の補足（折りたたみ details）

### 行コメントに置く情報

- 各指摘 1 件 = 行コメント 1 件
- ヘッダー行に分類とタイトル（例: `**[must-fix / M1] ...**`）
- 何を指摘しているか、該当箇所、なぜ問題か、対処案
- 対処案に diff 風のコードブロックを添えると作成者が取り込みやすい

### 行指定できない指摘の扱い

- PR 本文の表現・全体方針・PR 間の整合性など、特定の行に紐付かない指摘は**トップコメントに直接記載**
- または、最も関連性が高い行（例: PR 本文で触れているモジュールのエントリポイント）に意図的に紐付ける

### 複数指摘の同一ファイル配置

同じファイルに複数の指摘を付ける場合、スレッドを分けるため**文脈的に意味のある別々の行**に紐付ける（例: CPU Warning の NRQL に S1、CPU Critical の NRQL に S2）。同一行に複数コメントを重ねると視認性が落ちる。

### 使い分けの目安

| PR タイプ | 行コメント | トップコメント |
|---|:---:|:---:|
| ドキュメント PR | 該当段落に紐付けて分離 | 総評 + サマリ |
| インフラ PR | 指摘ごとに分離 | 総評 + サマリ |
| アプリ実装 PR | 指摘ごとに分離 | 総評 + サマリ |

---

## 対話フロー（ユーザー承認取得）

peer-review の**投稿前**は必ずユーザー対話で承認を取る。

### パターン A: 1 件ずつ解説モード（推奨）

指摘が多い場合、または新しいチーム / 慣れていないレビュアーの場合に有効。

```
1. ユーザーに指摘総数（must-fix X / should-fix Y / …）を報告
2. 「1 件ずつ解説し、PR 実装者にフィードバックするか判断する進め方で良いか」を確認
3. 各指摘を以下のフォーマットで 1 件ずつ解説:
   - 何を指摘しているか（1 文）
   - 該当箇所（PR 内の具体的な記述）
   - なぜ指摘したか（背景・根拠）
   - 影響（対応しない場合どうなるか）
   - 対処案（複数案ある場合、推奨付き）
   - 判断を仰ぐポイント（判断すべき論点）
4. ユーザーの判断を受けて、次の指摘へ進む
5. 途中で「以降は推奨で」と言われたら、残りを一括報告に切り替え
```

### パターン B: 一括報告モード

慣れたチーム / 少数指摘の場合。

```
1. 指摘一覧をまとめて表示（分類別に整理）
2. 各指摘の推奨対応を提示
3. ユーザーに AskUserQuestion で判定・投稿内容の確認を一括で取る
```

### 用語解説への対応

レビュー対象が専門的で、ユーザーに前提知識がないと判断が難しい場合:

- **日常語から段階的に解説**（CLAUDE.md の Communication Style 準拠）
- 「〇〇とは何か」から入り、技術用語は最後に紐づける
- 比喩・類比を活用（例: DMARC → 郵便システムの比喩）
- 判断に戻る前に「理解できましたか？」を確認

例: DMARC rua の解説
1. そもそもメールなりすましの問題（日常的な脅威）
2. SPF / DKIM / DMARC の 3 点セット（比喩: 郵便局、印鑑、ポリシー）
3. rua とは何か（レポーティング機能）
4. 今回の問題の本質（受信ボックスがない住所に送ろうとしている）

---

## CodeRabbit との棲み分け

### 原則

CodeRabbit は行レベル具体の自動レビュー、peer-review は俯瞰観点の人間レビュー。役割が異なるので、指摘を**重複させない**。

### 重複指摘への対応

- **CodeRabbit 指摘に賛同する場合**: トップコメントで軽く referrer（「CodeRabbit 指摘の通り、〜については対応をお願いします」）
- **CodeRabbit 指摘に反論する場合**: トップコメントで明示的に「CodeRabbit 指摘とは異なる意見ですが、〜」
- **CodeRabbit 指摘の対応方針を促す場合**: 「CodeRabbit 指摘（line X）への対応方針を PR 本文かコメントで明示していただけると助かります」

### CodeRabbit 指摘を peer-review でも取り上げる判断基準

- CodeRabbit 指摘が **設計の核心** に関わる場合は peer-review でも取り上げる
- CodeRabbit 指摘が **対応されないまま approve されている** 場合、対応方針確定を促す
- 上記以外は peer-review では触れない

---

## 投稿後の挙動

### 投稿コマンド

**行コメント付きレビュー**（原則）は Pull Request Reviews API を使う（`gh pr review` は行コメント未サポート）:

```bash
# /tmp/peer-review-<PR>-review.json を事前に jq で組み立てる（下記レシピ参照）
gh api --method POST /repos/<owner>/<repo>/pulls/<PR>/reviews --input /tmp/peer-review-<PR>-review.json
```

JSON 構造:

```json
{
  "event": "COMMENT" | "APPROVE" | "REQUEST_CHANGES",
  "body": "<トップコメント全文>",
  "comments": [
    {"path": "<file>", "line": N, "side": "RIGHT", "body": "<行コメント全文>"},
    ...
  ]
}
```

**行コメントが不要な場合**（俯瞰指摘のみ、極小 PR 等）は従来の `gh pr review` も可:

```bash
gh pr review <PR> --comment --body-file /tmp/peer-review-<PR>-top.md
# または --approve / --request-changes
```

### JSON 構築レシピ

各指摘 body を `/tmp/pr<N>-comments/{M1,M2,S1,...}.md` に個別ファイルとして書き出した後、jq で組み立てる:

```bash
jq -n \
  --rawfile top /tmp/pr<N>-comments/top.md \
  --rawfile m1  /tmp/pr<N>-comments/M1.md \
  --rawfile m2  /tmp/pr<N>-comments/M2.md \
  '{
    event: "COMMENT",
    body: $top,
    comments: [
      {path: "path/to/file", line: 10, side: "RIGHT", body: $m1},
      {path: "path/to/file", line: 42, side: "RIGHT", body: $m2}
    ]
  }' > /tmp/peer-review-<PR>-review.json
```

`line` は **変更後の新ファイル行番号**。新規追加ファイルなら diff の hunk offset を引いた値。

### 既存レビューの扱い（再投稿が必要になった場合）

PR レビューは **削除不可**。body 更新のみ可能:

```bash
gh api --method PUT /repos/<owner>/<repo>/pulls/<PR>/reviews/<OLD_REVIEW_ID> \
  -f body="このレビューは別形式で再投稿しました: <新 review URL>"
```

新 review 投稿後、古い review の body を誘導文に差し替える運用が安全。

### 投稿後検証

```bash
gh pr view <PR> --json reviews --jq '.reviews[-1] | {author, state, submittedAt, bodyLength: (.body | length)}'
```

### 投稿報告

ユーザーに以下を報告:
- PR URL
- 投稿時の state（COMMENTED / APPROVED / CHANGES_REQUESTED）
- 本文文字数
- 次に期待される作成者アクション（返信 / 修正 / Issue 起票）

### 投稿後のアクション

- 作成者からの返信待ち（本スキルではここで終了）
- 返信が来たら `review-pr`（reviewee 側）ではなく、**peer-review の対話モード** で再レビュー or 追加コメントを検討
- 最終的に approve する際は `gh pr review <PR> --approve` を別途実行
