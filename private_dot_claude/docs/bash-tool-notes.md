# Bash ツールの環境メモ

Claude Code の Bash ツールを使うときに、この環境で実際に起きる挙動をまとめる。常時読み込みはされない。詰まったときに読む。

## 複合コマンドは権限確認で止まる

`;` や `&&` で複数のコマンドを 1 行に繋ぐと、個々のコマンドが許可リスト（`Bash(gh *)` 等）に入っていても権限確認が出て停止することがある。応答が返らないため「固まった」ように見える。許可リストへ項目を足しても解消しない。

2026-08-31 の実測:

| コマンドの形 | 結果 |
|---|---|
| `gh pr view 6910 --repo mationinc/macaron --json commits`（単体） | 通る |
| `gh api graphql -f query='query{...}'`（単体） | 通る |
| 上の 2 つを `;` で繋ぎ、見出しの `echo` と `2>&1 \| head -60` を足した形 | 停止 |

対策: 1 回の Bash 呼び出しに 1 つの目的を割り当てる。複数の結果を見たいときは、繋ぐのではなくファイルへ落として次の呼び出しで読む。

## codex をコマンド位置に書くとフックが拒否する

PreToolUse フック `hooks/block-codex-direct.py` は、コマンド位置のトークンの basename が `codex` の実行を deny する（`codex exec` / `timeout 60 codex` / `FOO=1 codex` / `$(codex ...)` / バッククォート / `>/tmp/out codex`）。2026-09-11 の書き換え（dotfiles PR #75）以降は、クォート文字列・コメント・heredoc 本文を除いてから検査するので、grep パターンや heredoc 本文に `codex` で始まる行があっても拒否されない。例外は、複数行のダブルクォート内で始まるコマンド置換の中の heredoc（dotfiles Issue #113）。

- Codex の呼び出しは `codex:rescue` 経由に統一する（対話は `/codex:rescue`、委譲は `codex-rescue` サブエージェント）
- レビュー系スキル同梱の `bash .../codex-review.sh` のようなスクリプト呼び出しは検査対象外
- Codex に渡すプロンプト本文は Write ツールでファイルにしてパスを渡す（長文はコマンド文字列に埋めない、という理由でこの運用は変えない）

## 長い本文はファイル経由で渡す

`gh issue create` / `gh pr create` の本文のように、日本語や改行を多く含む文字列をコマンド文字列に直接埋めるとクォートが崩れやすい。`--body-file` などファイル経由の引数を使う。短い 1 行のタイトルだけはコマンド文字列に書いてよい。

## auto mode では複合コマンドと python / node が判定に回る

auto mode 中は、`Bash(python3 *)` `Bash(node *)` `Bash(npx *)` のような任意コード実行の許可と、`&&` / `;` / heredoc でつないだ複合コマンドが `permissions.allow` を通らず、毎回判定（classifier）に回る。2026-09-29 の棚卸しでは、直近 7 日に止まった 83 件がほぼ全部この形だった。判定の仕組みと止まったときの手順は `docs/auto-mode.md`。

- 1 回の Bash に 1 つの目的（上の「複合コマンドは権限確認で止まる」と同じ対策）
- ファイルの読み書きは Read / Edit / Write を使う。作業ディレクトリ内なら判定を通らない
- 止まった直後に同じ操作を小分けや別経路で通そうとしない。"Auto-Mode Bypass" として止まる

## 記録

- 2026-09-29: auto mode の節を追加（dotfiles の `docs/auto-mode.md` と同時）。
- 2026-09-09: 旧 `rules/tool-call-hygiene.md` から、環境固有の事実だけをこの文書へ移した。同ルールの大半（引数の書き方で parse エラーを防ぐ規範）は Opus 4.7/4.8 時代の対策で、直近 400 セッションで parse エラーが 0 件だったため撤去した（dotfiles Issue #89 / #90）。
