---
name: poc-feedback-triage
description: meimei（business-card-registry）の PoC フィードバック表を GitHub の Issue と突き合わせる。未対応の行は既存の Issue に対応付けるか起票し、対応付け済みの行は Issue と本番反映の状態からステータスを更新して、朝の報告を出す。平日の朝に launchd（com.h-suzuki.poc-feedback-triage）が実行する。手で「PoC のフィードバックを確認して」と頼まれたときにも使う。
---

# PoC フィードバックの突き合わせ

PoC の参加者が書く Google スプレッドシートを、GitHub の Issue と突き合わせる。表を最新の状態にしたうえで、朝の報告を Markdown で標準出力に出す。

決まり（2026-10-07 のユーザー決定）:

- 既存の Issue に無いフィードバックは、確認を取らずに起票する
- 本番に反映されたら、完了にして完了日を入れる
- 報告はローカルに残し、Mac の通知を出す。保存と通知は起動スクリプト（`~/.local/bin/poc-feedback-triage`）が行う。このスキルは報告を標準出力に出すだけ

## 対象

| 項目 | 値 |
|---|---|
| 表 | 「名刺管理ツールPOC報告」`1vi7fxI8_P5yi_t9jUAR_LbQ2jfMfnhBpUWFSl5C5iFM`、タブ `不具合管理表`（gid 0） |
| 見出し | 7 行目。データは 8 行目から |
| 列 | B 管理ID / C 報告日 / D 報告者 / E 対象機能 / F 概要 / G 再現手順 / H 重要度 / I 優先度 / J ステータス / K 担当者 / L 対応内容・進捗 / M 完了日 / N 備考 |
| ステータス | 新規 / 調査中 / 対応中 / 検証中 / 完了 / 保留（J 列のプルダウン） |
| repo | `mationinc/business-card-registry`（作業ディレクトリ） |

## してはいけないこと

- B〜I 列と K 列を書き換えない。報告者の欄である。管理 ID が空でも埋めない（N 列に「管理 ID が未記入」と書くだけ）
- 人が付けた「保留」と「完了」を戻さない
- コードを変えない。コミット・push・PR の作成・マージ・ワークフローの起動をしない
- Issue に報告者の名前を書かない。「PoC の参加者」と書く
- ユーザーが決めていないこと（方式・フェーズ・見た目の値）を決定として書かない。案は「修正案」、未定は「決まっていないこと」に書く

## コマンドの打ち方（無人実行の許可に合わせる）

launchd からの実行は `--permission-mode dontAsk` で、許可リストに一致するコマンドだけが通る。照合はコマンド 1 つごとに行われる。

- 1 回の Bash では、コマンドを 1 つだけ実行する。`&&` / `;` / パイプ / `for` ループでつながない。Issue を何本も見るときは、`gh issue view` を 1 本ずつ別の Bash で呼ぶ
- ファイルは作らない（Write ツールも無人実行では通らない）。表への書き込みは、内容を `--json` の引数で渡す（手順 5）
- 書き込みスクリプトは絶対パスで呼ぶ。変数（`$TMPDIR` など）を使わない
- 止められたら、同じことを別の形で通そうとしない。報告の「気づいたこと」に、止められたコマンドを書く

## 手順

### 1. 表を読む

```bash
command gws sheets spreadsheets values get --params '{"spreadsheetId": "1vi7fxI8_P5yi_t9jUAR_LbQ2jfMfnhBpUWFSl5C5iFM", "range": "不具合管理表!A8:N300"}'
```

F 列（概要）が空の行は読み飛ばす。読めないとき（認証切れなど）は、ここで止めて報告の先頭に「表を読めなかった」と理由を書く。

### 2. 行を分ける

- L 列に `#数字` が無い行は、まだ処理していない。手順 3 へ進む
- L 列に `#数字` がある行は、対応付けが済んでいる。手順 4 へ進む。N 列の番号は参考なので見ない

### 3. 未処理の行を対応付けるか、起票する

1. 既存の Issue を探す。概要の語を 2〜3 通りに言い換えて検索する。`poc-feedback` ラベルの Issue と、Epic「スマホ対応と操作性の改善」（#473）の子も見る

   ```bash
   gh issue list -R mationinc/business-card-registry --state all --limit 30 --search "<語> in:title,body" --json number,title,state
   ```

2. 同じ問題を扱う Issue があれば、それに対応付ける。ステータスは手順 4 の決まりで付ける。一部しか扱っていなければ、扱っていない残りを起票する
3. 無ければ起票する。種類とつなぎ先は次のとおり

   | フィードバック | Issue の種類 | マイルストーン | 親 |
   |---|---|---|---|
   | 動かない・壊れている | Bug | MVP | なし |
   | 今ある画面の使いにくさ | Task | MVP | 画面ならスマホ対応の Epic（#473） |
   | 新しい機能・作り方の要望 | Request | なし | なし |

   ```bash
   gh issue create -R mationinc/business-card-registry --title "<何をするか>" --body-file <本文> --label poc-feedback [--milestone MVP]
   gh api -X PATCH repos/mationinc/business-card-registry/issues/<番号> -f type=Task   # Bug / Request も同じ
   id=$(gh api repos/mationinc/business-card-registry/issues/<番号> --jq .id)
   gh api -X POST repos/mationinc/business-card-registry/issues/473/sub_issues -F sub_issue_id="$id"   # 親を付けるときだけ
   ```

   本文は日本語で、次の節にする。コードを読んで、今の作りと考えられる原因を具体的に書く（ファイル名・値・画面名）。

   - 親 Epic（あれば 1 行目に `親 Epic: #473`）
   - `## 何が起きているか`: 「PoC の参加者から〜と報告があった（PoC フィードバック表の管理 ID <ID>、<報告日> 報告）」と、今の作り
   - `## 考えられる原因`（分かる範囲で）
   - `## 修正案`
   - `## 完了の定義`: チェックボックス。最後に「報告者に確かめてもらい、PoC フィードバック表の <ID> のステータスを更新する」
   - `## 関連`（関係する Issue）
   - `## 規模`（SP の目安）

4. 起票した Issue のステータスは、原因が分からなければ「調査中」、直し方が決まっていれば「対応中」、ユーザーの判断待ちなら「新規」にする

### 4. 対応付け済みの行のステータスを更新する

L 列の Issue ごとに、状態と閉じた PR を見る。

```bash
gh issue view <番号> -R mationinc/business-card-registry --json state,closedByPullRequestsReferences
gh pr view <PR> -R mationinc/business-card-registry --json mergeCommit,mergedAt
```

本番に反映済みのコミットは、prod 環境のデプロイで成功した最新のものとする。

```bash
gh api "repos/mationinc/business-card-registry/deployments?environment=prod&per_page=10" --jq '.[] | "\(.id) \(.sha) \(.created_at)"'
gh api repos/mationinc/business-card-registry/deployments/<id>/statuses --jq '.[0].state'   # success のうち最新を使う
git fetch -q origin main
git merge-base --is-ancestor <マージコミット> <本番のコミット>   # 終了コード 0 なら本番に入っている
```

| L 列の Issue の状態 | ステータス | 完了日（M 列） |
|---|---|---|
| すべて閉じ、閉じた PR がすべて本番に入っている | 完了 | 本番に入った最初のデプロイの日（JST、`2026/10/09` の形） |
| すべて閉じたが、本番にまだ入っていない PR がある | 検証中 | 空 |
| 開いた Issue があり、それを閉じる PR がある | 対応中 | 空 |
| それ以外 | 変えない | 変えない |

PR を介さずに閉じた Issue（重複・対応しない）は、理由を Issue のコメントで確かめ、L 列に書く。ステータスは「保留」にし、報告の「気づいたこと」に挙げる。

### 5. 表に書く

L 列と N 列は「・」で始まる短い箇条書きを、改行でつないで書く。1 行は 25 字ほどに収める。Issue は `#123` と書けば、スクリプトがリンクにする。経緯の説明は書かない。詳しい中身は Issue に任せる。

```text
・シャッターを大きくする改修を起票
・今の外形は 72px のまま
・Issue: #496
```

変える行だけを JSON の配列にし、`--json` の引数でスクリプトに渡す。改行は JSON の `\n` で書く。シングルクォートで囲み、中身にシングルクォートを使わない。

```bash
python3 -I /Users/h-suzuki/.claude/skills/poc-feedback-triage/scripts/write-cells.py --json '[{"row": 8, "status": "完了", "done": "2026/10/09", "progress": "・シャッターを大きくした\n・Issue: #496"}]'
```

書いたあと、値を読み直して反映を確かめる（手順 1 の get を範囲 `J8:N300` で）。

### 6. 報告を出す

標準出力に、次の形の Markdown だけを出す。前置きは書かない。1 行目は通知の本文にもなるので、40 字ほどで結論を書く。

```markdown
PoC FB: 新規 1 件を起票、2 件を完了に更新

| 管理 ID | 概要 | ステータス | Issue |
|---|---|---|---|
| mei004 | … | 新規 → 調査中 | [#500](https://github.com/mationinc/business-card-registry/issues/500)（起票） |

## 起票した Issue
- [#500](URL) タイトル（種類・マイルストーン）

## 気づいたこと
- 同じ要望が 2 件ある、管理 ID が空の行がある、など。無ければ節ごと省く
```

変化が無い日は、1 行目を「PoC FB: 変化なし（全 N 件）」にして、表を省く。
