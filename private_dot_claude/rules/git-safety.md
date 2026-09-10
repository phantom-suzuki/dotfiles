# Git Safety

## 機械的に止まる操作

次の操作は settings.json の deny と tameny-base プラグインの PreToolUse フックが拒否する。回避策を探さない。

- `git push --force` / `-f`（`--force-with-lease` は可）
- `git reset --hard`、`git clean -f`、`git checkout .` / `git restore .`
- `--no-verify`
- `main` / `master` / `develop` / `release/*` への直接 push
- `gh pr merge`
- `git rebase`（この環境では deny。取り込みは `git merge` で行う）

## 判断が要る操作

- PR のマージは、ユーザーが「マージして」と明示したときだけ行う。「マージまで進めて」のような曖昧な表現では PR 作成まで行い、マージ前に確かめる。マージ前に `git status` が clean で `git log @{u}..HEAD` が空であることを確認する。未 push のコミットがあると squash マージの内容から抜け落ちる（2026-07-08 に発生）
- force push が本当に必要なときは `--force-with-lease` を使い、理由を伝え、`git fetch && git log origin/<branch>..` で他人の push が無いことを確かめる
- 見慣れないファイルやブランチは作業中のものかもしれない。消す前に調べる。未コミットの変更を捨てるより `git stash` を使う
- コミットは amend せず新しく作る（頼まれたときだけ amend する）

## squash マージ後のローカル main の同期

ローカル `main` が `origin/main` と分岐して見えるのは、squash 前の複数コミットと squash 後の 1 コミットが同じ内容で違うハッシュを持つため。

1. `git diff origin/main..main --stat` が空であることを確かめる。空でなければ別の変更が混ざっているので reset しない
2. `git checkout main && git reset --mixed origin/main`（`--hard` は使わない。作業ツリーに触れない）
3. feature ブランチは `git branch -d` が未マージと誤検知する。手順 1 を確認済みなら `-D` で消してよい

## コンフリクトの解消

`git fetch origin` のあと `git merge origin/<base>` で取り込み、ファイルごとに手で解消して `git add` し、マージコミットを作って通常の push をする。rebase は deny されているので使わない。
