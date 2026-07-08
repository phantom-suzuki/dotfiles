# L2 Codex を worktree + codex:codex-rescue で回す手順

pr-reviewer の L2（実コード検証）を Codex で回すための、この環境固有の手順。

## なぜこの手順が要るか

2 つの制約がある。

1. **Codex の Bash 直叩きはフックにブロックされる**。`codex exec` はもちろん、`peer-review` スキルの `codex-review.sh`（内部で `codex` を直叩き）も、この環境では失敗する（`line 76: : No such file or directory` 等の症状）。グローバル規約で Codex 直叩きが封じられているため。→ **`codex:codex-rescue` サブエージェント（codex-companion ランタイム）経由でのみ Codex を使う**。
2. **Codex は「現在チェックアウト中のブランチと base の diff」を見る**。別のブランチで作業している最中に対象 PR をレビューさせると、無関係な diff を見てしまい失敗・誤レビューになる。→ **対象 PR ブランチを `git worktree add` で別ツリーに取り出し、そのパスを Codex に渡す**。

## 手順

### 1. 最新取得と worktree 作成

fork からの PR は head ブランチが `origin` に存在しないため、`origin/<head ブランチ>` 形式では解決できない。**head は PR のメタデータから `headRefOid`（コミット SHA）を取得**して worktree を作る。base（`BASE_REF`）は SKILL.md Step 1 のトリアージで既に取得済みの `baseRefName` を再利用する（同じ値を取り直さない）。

```bash
git fetch origin --quiet   # セッション開始時に 1 回だけ（複数 PR を処理する場合もループの外で 1 回）
SCRATCH="<scratchpad ディレクトリ>"   # セッションの一時領域
HEAD_SHA=$(gh pr view <N> --repo <owner>/<repo> --json headRefOid --jq '.headRefOid')
git fetch origin "$HEAD_SHA" --quiet   # fork の PR でも GitHub 側で到達可能な SHA は fetch できる
git worktree add "$SCRATCH/wt-<N>" "$HEAD_SHA"
```

- `BASE_REF`: Step 1 で取得した `baseRefName` をそのまま使う。次項の `codex:codex-rescue` プロンプトに渡す base ブランチ名（`origin/main` 固定ではなく、PR ごとの実際の base を使う）。
- `HEAD_SHA` を使うことで、同一リポジトリの PR・fork からの PR のどちらでも同じ手順で worktree を作れる。
- 複数 PR は worktree を並べて作る（`wt-1137` / `wt-1122` …）。detached HEAD で問題ない。

### 2. codex:codex-rescue に委譲（複数 PR は並列）

各 PR について `codex:codex-rescue` サブエージェントを起動する。複数 PR は同一メッセージで並列起動する。プロンプトに含める要素:

- **作業ディレクトリ**: 該当 worktree の絶対パス
- **文脈**: 「この worktree は PR #<N> のブランチ。base は `$BASE_REF`」
- **やること**: `git diff origin/$BASE_REF...HEAD` で変更を確認 → 独立したセカンドオピニオンとして俯瞰レビュー
- **観点**: ドキュメント PR なら「文書の主張がリポジトリ実体（ファイルパス・script 定義・用語集）と整合するか、実際に grep/ls で確認」「参照リンク・アンカーの解決」「論理矛盾・抜け漏れ」。コード PR なら「変更の論理整合・実装到達度・実装レベルの security」
- **出力形式**: must-fix / should-fix / question / nit / praise に分類し、各指摘に該当箇所（ファイル:行 or 節名）を添えて日本語で返す。actionable な指摘がなければ「actionable な指摘なし」と明記

### 3. 結果の裏取り

Codex の指摘も間違うことがある。**採用する前に自分で `grep`/`ls` して裏取り**する。特に「ファイルが実在しない」「script が未定義」「用語集と不一致」のような事実主張は、投稿前に必ず確認する。裏が取れた指摘だけを Step 3 の統合に回す。

### 4. 後片付け

レビュー・投稿が済んだら worktree を削除する。

```bash
git worktree remove "$SCRATCH/wt-<N>" --force
git worktree prune
git worktree list   # 元の作業ツリーだけ残ることを確認
```

## codex:codex-rescue プロンプト雛形

```text
作業ディレクトリ: <worktree の絶対パス>

このディレクトリは GitHub PR #<N> のブランチをチェックアウトした git worktree です（<owner>/<repo>）。base は origin/$BASE_REF です。

以下を実施してください（Codex に委譲）:
1. `git diff origin/$BASE_REF...HEAD` で PR の変更内容を確認する。
2. 変更の概要: <ここに PR の内容を 1-2 文で>
3. 独立したセカンドオピニオンとして俯瞰観点でレビュー:
   - <観点を列挙。実体との整合は必ず grep/ls で確認させる>
4. 指摘を must-fix / should-fix / question / nit / praise に分類し、各指摘に該当箇所（ファイル:行 or 節名）を添えて簡潔に返す。actionable な指摘がなければ「actionable な指摘なし」と明記。
最終回答は日本語で、分類済みの箇条書きで返してください。
```
