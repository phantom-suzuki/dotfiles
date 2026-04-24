# Self-Review Skill 改善案: 大規模 diff 対応

> Created: 2026-04-22 (JST)
> Context: PR #398 (mationinc/wp-platform, 34 files / 1046 lines) の self-review 実行時に、Codex review が 5 分タイムアウト、Gemini が容量不足/JSON パース失敗で全滅し、Claude-p 1 件のみで cascade 終了。しかも Claude-p 3 findings のうち 2 件が誤検知で、実質 actionable 0 件だった。
> Status: Draft — 別セッションで実装予定

## 問題の根本原因

今回の self-review cascade での失敗パターン:

| 問題 | 観測 | 原因推定 |
|-----|-----|---------|
| Codex review 5 分タイムアウト | diff 72KB / 34 ファイル | 全観点（バグ/セキュリティ/エラー/設計）を 1 プロンプトで依頼、内部的に逐次解析 |
| Gemini 429 / 2.5-flash JSON 打ち切り | 3 リトライ全滅 | diff が大きく応答が切れ、JSON 構造が壊れる |
| Claude-p 誤検知率高 | 3 件中 2 件 false positive | 短時間で全観点を広く見たため浅いレビューに |

共通する構造問題: **大規模 diff × 広い観点** を 1 リクエストに詰めているため、どのレビュアーも「広く浅く」になり、失敗または低品質化する。

## 改善案

### 🟢 案 A: Codex タイムアウト短縮 + 早期フォールバック（最小変更）

```text
cascade で Codex の timeout を現行 300s → 120s に短縮
タイムアウトしたら即 Gemini / Claude-p の結果で代用し先へ
```

- **Pros**: スキル最小変更（timeout 値とフォールバック分岐のみ）
- **Cons**: 根本解決ではない。Codex が使えないケース自体は残る
- **実装コスト**: 小（`references/review-prompts.md` の数値変更のみ）

### 🟡 案 B: 観点別並列（推奨）

大規模 diff（`≥ 500 行 or ≥ 20 ファイル`）を自動検出した場合、観点をレビュアーに分散する:

| 観点 | 担当レビュアー | プロンプト重点 |
|-----|-------------|--------------|
| バグ・ロジック | Claude-p | 条件分岐・境界値・エラー伝播・非同期順序 |
| セキュリティ | Codex | インジェクション・認証不備・シークレット漏洩・権限昇格 |
| 設計・アーキ | Gemini | 責務分離・依存方向・API 一貫性・DRY/YAGNI |

並列起動 → 結果マージ → 同ファイル±5行の重複除去。

- **Pros**:
  - 各レビュアーが 1 観点に絞って深く見られる
  - プロンプトが短くなり応答も速い
  - 全体時間は並列分短縮（最長のレビュアー時間で決まる）
  - レビュアーの得意分野を活かせる
- **Cons**:
  - 観点横断の問題（例: 設計×セキュリティの交差）が落ちる可能性 → マージ時にラベル付与してユーザーに info 表示
  - 各レビュアーの結果品質が不均一になる可能性
- **実装コスト**: 中（prompt テンプレート 3 種追加、並列実行ロジック、マージロジック）

### 🟠 案 C: ファイルチャンク × 観点の二軸並列（大規模向け）

大規模 diff をファイル系統でチャンク化し、各チャンク × 各観点を並列実行する（最大 M×N ジョブ）:

```text
チャンク分類例:
- Infrastructure (terraform/modules/*, terraform/environments/*)
- Docs (*.md)
- Application (src/*, lib/*)

実行: Infrastructure × {バグ, セキュリティ, 設計} = 3 並列
      Docs × {設計, 一貫性} = 2 並列
      Application × {バグ, セキュリティ, 設計} = 3 並列
合計 8 並列ジョブ
```

- **Pros**: 真の並列化で 60 秒以内に完了見込み
- **Cons**: 実装複雑、API レート制限リスク、ファイル横断の問題検知ロジックが必要
- **実装コスト**: 高

## 推奨: 案 B を次の実装ターゲット

理由:
- ユーザー提案（観点分割 + 並列）をセットで実現
- 各レビュアーの特性を活かせる（Codex はセキュリティ強、Gemini は設計視点、Claude-p は速い）
- 案 A の効果（タイムアウト削減）も自動的に含む
- 案 C ほど複雑化せず、現行スキルの `strategy: parallel` を拡張する自然な進化になる

## 実装ガイド（案 B）

### 1. 対象ファイル

- `~/.claude/skills/self-review/SKILL.md` — strategy 判定ロジックと Step 3 の parallel モードに「観点別並列」分岐を追加
- `~/.claude/skills/self-review/references/review-prompts.md` — レビュアー別プロンプトを観点別に 3 種に再構成
- `~/.claude/skills/self-review/references/review-prompt-template.md` — 観点別テンプレート（`bug.md`, `security.md`, `design.md` 等に分割）を追加
- `~/.claude/skills/self-review/scripts/gemini-review.sh` — 観点パラメータ対応（環境変数で受け取り）

### 2. 判定ロジック

```text
既存の strategy: auto 判定を拡張:

diff ≤ 500 行 かつ ファイル ≤ 10 → parallel (従来通り、2 レビュアー並列)
500 行 < diff ≤ 2000 行 または 10 < ファイル ≤ 40 → parallel-by-aspect (案 B)
それ以外 → cascade (案 C は今回不採用、次フェーズ)
--deep 指定時 → cascade 強制（精度優先）
```

### 3. 観点別プロンプトの構成

`references/review-prompt-template.md` を以下のように分割する:

```
references/
  review-prompt-template.md (共通: 出力 JSON スキーマ、category 分類ルール)
  review-prompt-bug.md (バグ・ロジック専用の観点 + 例示)
  review-prompt-security.md (セキュリティ専用)
  review-prompt-design.md (設計・アーキ専用)
```

呼び出し時は共通テンプレート + 観点別テンプレートを結合してプロンプトを作る。

### 4. レビュアー割り当ての柔軟性

固定ではなく、以下のフォールバックを入れる:

```text
primary:
  bug → Claude-p
  security → Codex
  design → Gemini

fallback (primary が失敗した場合):
  bug → Gemini / Codex
  security → Claude-p / Gemini
  design → Claude-p / Codex
```

### 5. マージロジック

観点別 findings を統合する際:

1. 観点タグを各 finding に付与（`aspect: bug|security|design`）
2. 同一ファイル ±5 行の重複は **severity が高いほう + 複数観点のラベル付与** で統合
3. 最終サマリに観点別件数を出す（例: `bug: 3 / security: 1 / design: 5`）

### 6. 検証方法

実装後、今回の PR (feature/371-cost-allocation-tag-v2) を題材に再実行し、以下を確認:

- 全体所要時間が 5 分以内に収まる
- false positive が減少する（Claude-p の誤検知 2 件のような「既に実装済み」の指摘が減るか）
- 観点横断の問題が info に回されているか

## 副次改善候補（案 B 実装時に同時検討）

### B-1: 既存実装チェックの前処理

今回の Claude-p 誤検知 2 件はいずれも「既に実装されている機能を未実装と指摘」だった:
- `_dept_guard` による departments レジストリ突合 → 既に実装済み
- design-note の `PR TBD` → 既に `PR #398` に更新済み

プロンプトに **「diff のみを見て判断せず、該当ファイルの現在の全体を読むこと」** を強く明示するか、レビュー前に該当ファイルを `git show HEAD:<file>` で全体取得してプロンプトに添付する対応を入れる。

### B-2: サマリで false positive 率を可視化

レビュアー別の finding 件数と、ユーザーが「誤検知」と判断した件数を記録し、後で `/self-review --stats` で傾向を確認できるようにする。精度の悪いレビュアーに過度に依存する構造を防ぐ。

## 関連

- 現行スキル: `~/.claude/skills/self-review/SKILL.md`
- 参照ファイル: `~/.claude/skills/self-review/references/`
- スクリプト: `~/.claude/skills/self-review/scripts/gemini-review.sh`
- 実行履歴参考: mationinc/wp-platform PR #398 の self-review (2026-04-22)

## 実装優先度

次に self-review が必要になるのは、PR #398 後の Prod 展開系 PR（#343 smakon.jp Prod、#394/#395 post-merge 系）。それらは今回より規模が大きい可能性が高いため、**Sprint-5 の技術投資枠で実装する** のが現実的。

## 実装履歴

### 2026-04-25: Gemini プリフライト + リトライ削減 + クールダウン（本ドキュメントの案とは別軸のレイテンシ改善）

上記の案 A/B/C は「大規模 diff でのレビュー精度・分散」がテーマだが、それとは別軸で **「Gemini が容量不足 (429) のときに無駄な待機を減らす」** チューニングを実装済み。

変更:
- 新規: `scripts/gemini-preflight.sh` — 軽量プローブで pro/flash の可用性を事前判定、結果を `.gemini-cooldown` に 15 分 TTL でキャッシュ
- 修正: `scripts/gemini-review.sh` — MAX_RETRIES=3 → 1、BASE_WAIT=5 → 3、`GEMINI_STATUS=flash-only` 受け入れ、429 時にクールダウン書き込み
- 修正: `SKILL.md` — Step 0.5（プリフライト実行）追加、cascade/parallel-by-aspect のフォールバック記述更新

効果: Gemini 不調時の待機が **最大 ~70s → 初回 ~10s / 15 分以内の再実行 0.015s** に短縮。案 A（Codex timeout 短縮）と同じく「早期フォールバック」系の改善だが、対象は Gemini の 429 検出パス。

未着手: 案 B（観点別並列）、案 C（ファイル×観点の二軸並列）は引き続き次フェーズ。
