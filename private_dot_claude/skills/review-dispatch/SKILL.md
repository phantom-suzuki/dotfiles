---
description: レビュー依頼を受けたとき、6 つのレビュースキル（self-review / review-pr / peer-review / review-adr / review-doc / dependabot-review）から最適なものを判定する分岐ガイド。「どのレビュー使う？」「レビュースキル使い分け」「review-dispatch」「レビュー判定」等の依頼時、または対象が曖昧で起点となるレビュースキルを 1 つに絞れないときに使用。
argument-hint: ""
---

# Skill: /review-dispatch

## 概要

レビュー対象（コード / PR / ADR / ドキュメント / Bot PR）と立ち位置（自分 / 他者 / レビュー受け側）の組合せから、最適なレビュースキルを判定する軽量分岐ガイド。

このスキル自体はレビューを実行しない。判定後に該当スキルを起動する。

## 6 スキル早見表

| スキル | 対象 | 修正権限 | 出力先 | 主観点 |
|---|---|---|---|---|
| `/self-review` | 自分のコード差分 (changed/staged/all) | あり（自動コミット） | git commit | バグ・品質・複雑さ |
| `/review-pr` | 自分の PR についたレビューコメント | あり（コード修正 + GraphQL 返信） | review thread reply + resolve | 受けた指摘への対応 |
| `/peer-review` | 他者の PR | なし | PR review API（行コメント + トップ） | security / arch / goal / alternatives / spec |
| `/review-adr` | 単一 ADR (.md, docs/adr/) | なし（提案のみ） | 標準出力（Edit は承認後） | 論理一貫性・既存矛盾・抜け漏れ・軸選定・表記 |
| `/review-doc` | 通常 Markdown ドキュメント（ADR 以外） | なし（提案のみ） | 標準出力（Edit は承認後） | 可読性・前後整合・参照リンク・更新漏れ |
| `/dependabot-review` | Bot 作成 PR (Dependabot/Renovate) | なし（追従 PR は承認後・別ブランチ） | PR コメント upsert | バージョン bump 追従漏れ（grep） |

## 判定フロー

```
Q1: 対象は何か？
  ├─ ADR (.md, docs/adr/) ──────────────→ /review-adr
  ├─ Bot (Dependabot/Renovate) 作成 PR ───→ /dependabot-review
  ├─ ADR 以外の Markdown ドキュメント
  │   (README, ガイド, spec, RFC, 技術記事 等) → /review-doc
  └─ コード / 普通の PR → Q2 へ

Q2: 対象は誰のもの？
  ├─ 他者の PR ─────────────────────────→ /peer-review
  └─ 自分のもの → Q3 へ

Q3: 自分のもののどのフェーズ？
  ├─ PR 作成前 / マージ前のセルフチェック ──→ /self-review
  └─ 自分の PR にレビューコメントがついた ──→ /review-pr
```

## 起点語からの逆引き

依頼語句が明確な場合は、判定フローをスキップして直接該当スキルを起動して構わない。

| 起点語例 | 対象 | スキル |
|---|---|---|
| 「セルフレビュー」「レビュー回して」「self-review」 | 自分のコード差分 | `/self-review` |
| 「レビュー対応」「レビューコメントに返信」「review-pr」 | 自分の PR についたレビュー | `/review-pr` |
| 「PR レビュー」「ピアレビュー」「他者の PR を見て」 | 他者の PR | `/peer-review` |
| 「ADR レビュー」「ADR を見て」 | ADR (.md, docs/adr/) | `/review-adr` |
| 「ドキュメントレビュー」「ガイドを見て」「Markdown レビュー」 | 通常 Markdown | `/review-doc` |
| 「dependabot レビュー」「依存性 PR を見て」「bot PR チェック」 | Bot 作成 PR | `/dependabot-review` |

### `/self-review` の主な opt-in フラグ（参考）

軽量化のためデフォルト経路は **bug + security の 2 並列** に絞られている。重厚化が必要な場合は以下を明示指定:

| フラグ | 効果 |
|---|---|
| `--with-design` | design 観点を追加（claude -p、`--with-gemini` 時は Gemini） |
| `--with-gemini` | Gemini を経路に組み込む（プリフライトもこの時のみ起動） |
| `--ultrareview` | bug の primary を `claude ultrareview --json` に置換（課金あり） |
| `--deep` | `standard` を superset、design + ultrareview + max-iterations 3 を自動有効化 |
| `--simplify-via=codex` | Simplify を codex exec に委譲（デフォルトは内蔵 `/simplify`） |
| `--force-external` | diff が小さく `simple` 自動判定された場合でも外部レビューを強制実行 |

## 特殊ケース

### ADR を含む PR

PR 全体を `/peer-review` で俯瞰しつつ、ADR ファイルは個別に `/review-adr` で深掘りする 2 段構成。

優先順位:
1. `/peer-review` で PR 全体（コード + ADR + ドキュメント）の俯瞰指摘を収集
2. ADR について論理一貫性・既存矛盾を深掘りしたい場合のみ `/review-adr` を追加実行
3. 重複指摘は peer-review 側に統合し、PR コメント投稿は 1 回に集約する

### 自分の PR に bot レビューがついた（CodeRabbit / gemini-code-assist 等）

→ `/review-pr` で対応する。

`/dependabot-review` は **bot が作成した PR** が対象であり、bot がレビューした PR は対象外。
「bot 作成 PR」と「bot レビュー」は別概念であることに注意。

### コード変更を含む Markdown PR（自分のもの）

- コードが主、Markdown は補助 → `/self-review`（Markdown も diff に含まれるためカバーされる）
- Markdown が主、コードは補助（マイグレーションガイドのような PR） → `/review-doc` を起点に、コード差分があれば `/self-review --skip-simplify --skip-external` で軽くチェック
- どちらが主か曖昧 → `/self-review` を先に走らせて、Markdown 観点が薄ければ `/review-doc` を追加

### スキル / プラグインの SKILL.md レビュー

→ 通常の Markdown とは性質が異なるため、`/review-doc` の対象外。
- 設計レビュー（観点・構造） → `/skill-design` 関連の助言を仰ぐ
- 実装変更を含む PR → `/self-review`（コード扱い）
- 他者の SKILL.md PR → `/peer-review`

## 実行手順（このスキル自体）

### Step 0: 入力受付

ユーザーから「○○をレビューして」のような依頼を受けたとき、以下を確認する:

1. レビュー対象の物理形式（ファイル / PR / 差分）
2. 対象が自分のものか他者のものか
3. すでに PR にレビューコメントがついているか

### Step 1: 判定

「判定フロー」に従って該当スキルを 1 つ特定する。曖昧な場合は AskUserQuestion で 2-3 候補から選択させる。

### Step 2: 該当スキル起動の提案

判定結果をユーザーに報告し、該当スキルの起動を提案する。例:

> 対象が自分のマイグレーションガイド（`docs/onboarding/migration-*.md`）なので、`/review-doc` を起点に推奨します。コード差分を伴う場合は `/self-review --skip-external` を併用できます。

ユーザーが承認したら、該当スキルを Skill ツール経由で起動する（あるいはユーザーに `/<skill-name>` を入力してもらう）。

## 注意事項

- このスキルは **判定のみ** で、レビュー本体は実行しない
- 起点語が明確（「セルフレビュー」「ADR レビュー」等）な場合は、判定をスキップして直接該当スキルを起動して構わない
- 該当スキルがない対象（コミットメッセージ、画像、設計図、Slack スレッド等）はユーザーに確認し、最も近いスキルを補助的に使うか、手動運用にフォールバックする

## 関連スキル

すべての判定先スキルは前掲「6 スキル早見表」を参照。

- `/self-review`
- `/review-pr`
- `/peer-review`
- `/review-adr`
- `/review-doc`
- `/dependabot-review`
