# Git Safety

## 機械的に止まる操作

次の操作は settings.json の `permissions.deny` が拒否する。エラーになるので回避策を探さない。

- `git push --force` / `-f`（`--force-with-lease` は可）
- `git reset --hard`、`git clean -f`、`git checkout .` / `git restore .`
- `git branch -D`（強制削除。`-d` は可）
- `--no-verify`（commit / push / merge）
- `main` / `master` への直接 push（`HEAD:main` や `refs/heads/main` の形も含む）
- `git rebase`（取り込みは `git merge` で行う）

## 確認プロンプトが出る操作

次の操作はブロックされず、承認を求めるプロンプトが出る。settings.json の `permissions.ask` が受け持つ。

- `develop` / `release/*` への直接 push
- 引数なしの `git push`（今いるブランチの upstream へ送る形。main 上で打つと deny をすり抜けるため）。push はブランチ名を明示して `git push -u origin <branch>` と書く

`gh pr merge` は 2026-09-19 にプロンプトの対象から外した。tameny-base プラグインのフックが、
ユーザーが「マージして」と明示した直後でも毎回確認を求めていたため。Claude Code にはフックを
1 つだけ無効にする設定が無いので、プラグインごと無効にし、必要な守りを上の deny / ask へ書き写した。
マージしてよいかの判断は、下の「判断が要る操作」の規律だけが受け持つ。

auto mode では、`gh pr merge` のような複合コマンドは allow を通らず自動の判定に回る。2026-09-29 に、ユーザーが「マージして」と明示した PR の `--admin` マージを、判定が "Merge Without Review" として止めた。
そこで、判定の許可の節（`autoMode.allow`）に「明示の指示を受けた PR の `gh pr merge`（`--admin` を含む）」と「定期実行からの条件付きマージ」を足した。値の正本は `~/.config/chezmoi/chezmoi.toml` の `[data.claude.autoMode]`、仕組みは `docs/auto-mode.md`。
判定が止めたときに、Claude が自分で許可を足すことはできない（Self-Modification として止められる）。提案ファイルを書き、適用はユーザーが行う。

## 判断が要る操作

- PR のマージは、ユーザーが「マージして」と明示したときだけ行う。プロンプトで止まらなくなったので、この規律だけが歯止めである。「マージまで進めて」のような曖昧な表現では PR 作成まで行い、マージ前に確かめる。マージ前に `git status` が clean で `git log @{u}..HEAD` が空であることを確認する。未 push のコミットがあると squash マージの内容から抜け落ちる（2026-07-08 に発生）
- 例外は、ユーザーがその会話で設定した定期実行（CronCreate）の取り込み判定だけ。CI が全緑、Greptile が現在の head をレビュー済み、未解決スレッド 0、ユーザーが指定した範囲内の PR に限って squash マージしてよい（2026-09-29 のユーザー判断）。条件を 1 つでも欠く PR は記録だけして触らない
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
