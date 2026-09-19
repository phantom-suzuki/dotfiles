# Global Claude Code Instructions

ユーザー向けの出力は日本語。文の組み立ては `rules/easy-japanese.md`、用語の選び方は `rules/terminology.md`、報告と質問の型は `rules/communication-style.md` と `rules/question-blocking.md` に従う。ここには常時効く要点だけを置く。

## 報告と質問

- 結論を先に 1 行で書き、続けて表か箇条書きで全体像を出す。完了報告は数行に収める
- 用語は業界標準の語で書く。IT の標準用語はカタカナや英語のままでよい（ミラー / スキップ / デプロイ / User-Agent）。標準用語を和語に置き換えない（写し / 飛ばし / 配信 は不可）。聞き慣れない語だけ初出で 1 句の説明を添える。決まりは `rules/terminology.md`、迷ったら `docs/glossary/` を引く
- Issue / PR 番号や手順の Step 番号は、番号だけで出さず「何を指すか」を言葉で添える。GitHub の Issue / PR 番号は本文では常に `[#123](URL)` のリンクにする。`AskUserQuestion` の中ではリンクを書けないので、「Percona Toolkit を導入する Issue（#7001）」のように名前を主語にして番号は括弧に入れる
- `AskUserQuestion` の質問文は本文と切り離して単独で読まれる。対象の名前・誰が・何を決めるかを質問文の中に入れ、指示語（この / その）や番号だけで始めない。番号だけ・記号・内輪語の質問は `hooks/check-question.py` が差し戻す。型は `rules/question-blocking.md`
- ユーザーの判断が要る場面（方針・設計案・スコープ・マージや外向き操作の可否）は `AskUserQuestion` で聞き、回答まで待つ。聞く前に判断材料を通常テキストで先に出す

## 委譲と並列作業

- 実装・修正・調査は自分で行うのが既定。委譲するのは次のいずれかに当たるとき: 並列化で時間が縮む / 大量のファイル読みや長い出力を主コンテキストから切り離したい / Codex が得意な領域（自律的な長い試行錯誤・Web リサーチ・画像生成）である
- 委譲するときもセッションコストを意識する。サブエージェントには目的と完了条件を短く渡し、コードは貼らずパスで示す。同じ作業への再委譲は 3 回までを目安にする。判断基準の詳細は `task-delegation` スキル
- Codex へ委譲するときはモデルと reasoning effort を毎回明示する。省くと `~/.codex/config.toml` の既定値に落ち、依頼の重さに合わなくなる。選び方は `skills/task-delegation/references/codex-routing.md`
- Slack の閲覧・検索・過去メッセージの調査は Codex に委譲する（Codex 側で `slack@openai-curated` プラグインが有効）。この CLI の Slack コネクタや Chrome 拡張の再認証をユーザーに頼まない。Codex の `mcp_servers` に slack が無くても「接続できない」と判断しない
- 複数 Issue を同時に進めるときは git worktree で分離する（同一ブランチなら Agent Teams、Issue 別ブランチなら worktree ごとに Agent）。手順は `parallel-work-decision` スキル
- diff の確認・コミット・push はユーザー確認の流れに残す（`rules/git-safety.md`）

## Markdown と Artifact

- リポジトリに残す Markdown（docs / README / ADR / 計画書 / ガイド）を新規作成・大幅改稿したら、`doc-polish` スキルで表現を研磨してから完成報告する
- Mermaid 図を書くときは `docs/mermaid-conventions.md` を読む（ダークモードの配色と、push 前の構文検証）
- HTML の Artifact にはライト / ダークの切り替えボタンを付ける。要件と雛形は `rules/artifact-conventions.md`

## Dotfiles（chezmoi）

個人設定（Ghostty / Neovim / zsh / tmux / Claude Code）は chezmoi で管理している。ソースは `~/.local/share/chezmoi/`、リポジトリは `github.com/phantom-suzuki/dotfiles`。

- ターゲット（`~/.config/...` や `~/.claude/...`）ではなく、必ずソース側を編集して `chezmoi apply` する。ターゲットを直接編集したら直後に `chezmoi re-add` する。`*.tmpl` は re-add できないのでソースを直接編集する
- 生成済みの `~/.claude/settings.json` を `chezmoi add` / `re-add` しない。トークンや API キーを tmpl に書かない
- 手順の詳細と落とし穴は `docs/chezmoi-workflow.md`
