# コンテキスト収集手順

俯瞰レビューは「diff を眺める」だけでは不可能。PR が達成しようとしている**目的**と、その**前提**（既存設計・Spec・ADR）を理解して初めて「目的達成度」「代替案」「Spec 整合」が評価できる。

このドキュメントは、PR レビュー前に必ず収集すべきコンテキストの体系を定義する。

---

## 収集対象の階層

```
L0: PR そのもの
L1: 直接参照される情報（PR 本文の Issue / ADR 参照）
L2: 間接参照される情報（関連する既存ドキュメント、CLAUDE.md）
L3: プロジェクト全体のコンテキスト（Steering、コーディング規約）
```

ドキュメント改訂系 PR は L2 まで、実装系 PR は L1 + L3 を重点的に収集する。

---

## L0: PR そのもの

### メタ情報

```bash
gh pr view <PR> --json \
  title,body,author,baseRefName,headRefName,files,additions,deletions,\
  state,url,commits,reviewRequests,reviews,labels,milestone
```

押さえるべき項目:
- **title / body**: 作成者の意図、達成目標、テスト計画
- **files / additions / deletions**: 変更の規模・散布
- **reviewRequests**: レビュアー指定（あなたが指名されているか）
- **reviews**: 既存レビュー（CodeRabbit / 他人間レビュアー）の指摘内容
- **labels / milestone**: 優先度・リリース計画上の位置付け
- **commits**: 各コミットメッセージ（diff の構造理解）

### diff

```bash
gh pr diff <PR> > /tmp/pr<PR>.diff
wc -l /tmp/pr<PR>.diff
```

- 3000 行超なら分割レビューを検討
- ドキュメント PR は diff 全文を読む
- 実装 PR は「新規ファイル全文 + 既存ファイル変更部分」を重点的に

---

## L1: 直接参照される情報

### PR 本文から Issue / Epic を抽出

PR 本文中の `#\d+`, `Epic #\d+`, `close #\d+`, `Refs #\d+` 等を全て抽出し、取得する:

```bash
gh issue view <N> --json title,body,state,labels,milestone
```

特に **Epic Issue の備考**は、PR 本文に書かれない設計前提が残っていることがある（命名規則、サブドメインパターン、他の制約）。**Epic 備考と PR 設計の不整合**は俯瞰レビューの重要な指摘ポイント。

### PR diff / 本文から ADR / Spec を抽出

PR 内で参照されるパス（例: `infra/docs/adr/001-*.md`, `infra/docs/plan/*.md`）を全て Read する。

特に注意:
- **ADR 自体が「承認済み」か「提案中」かを確認**（ステータス欄）
- ADR 番号が PR 本文と実ファイル名で食い違う場合あり（例: `001-amplify-branch-naming-convention.md` と `001-amplify-branch-naming-and-deploy-strategy.md` が並存）→ どちらが正本かを確認
- 外部リポの ADR を参照している場合（例: context-it ADR-002）、該当リポ内にファイルが無い → 参照先が不明確な指摘ポイント

---

## L2: 間接参照される情報

### 既存の同類ドキュメント

変更対象ファイルと**同じ役割を持つ別のドキュメント**を必ず確認する。責務分離の破綻・情報の二重管理が発生していないかチェックする。

例:
- `dns-domain.md` を更新する PR → `ses.md`, `architecture.md`, `networking.md` も確認
- 実装モジュールの PR → 既存の同類モジュールの実装パターンを確認

```bash
# 同ディレクトリの類似ファイル
ls <対象ファイルのディレクトリ>/

# 関連キーワードでの横断検索
grep -r "<キーワード>" <親ディレクトリ>/ --include="*.md" -l
```

### CLAUDE.md（該当領域）

対象ディレクトリの CLAUDE.md は、プロジェクト固有の規約・設計思想・禁止事項を記録している。俯瞰レビューの**判断基準**になる。

例:
- `infra/CLAUDE.md`: Terraform 規約、モジュール利用ルール、セキュリティ規約
- `backend/CLAUDE.md`: Go 規約、Clean Architecture 境界
- `frontend/CLAUDE.md`: TypeScript/React 規約

ルート CLAUDE.md は Steering 全体の把握にも使える。

### 既存コードベース（実装 PR の場合）

実装 PR の場合、**既存の類似実装パターン**を grep で確認する。ドキュメント PR と違い、既存実装との整合は非常に重要。

例（PR #2998 の M2 指摘）:
- ドキュメントが `default = ""` / `!= ""` を使っているが、既存実装は `default = null` / `!= null`
- **既存実装を grep で確認していれば**、この不整合が検出できた

```bash
# 既存実装パターンの検出
grep -rn "variable \"domain_name\"" infra/modules/
grep -rn "var.domain_name !=" infra/modules/
```

---

## L3: プロジェクト全体のコンテキスト

### Steering ファイル（Kiro SDD 採用プロジェクト）

`.kiro/steering/` 配下のファイルは**常時有効な設計原則**:

- `AI_POLICY.md`: AI 権限境界
- `DB_POLICY.md`: DB ポリシー
- `CONVENTIONS.md`: コーディング規約
- `REVIEW_CHECKLIST.md`: レビュー観点
- `TEST_POLICY.md`: テスト方針
- `WORKFLOW.md`: ワークフロー定義

これらは PR が暗黙に従うべき規約。違反していれば俯瞰レビューで指摘する。

### プロジェクトルートの CLAUDE.md と .claude/rules/

- `CLAUDE.md`: プロジェクト全体の設計思想、AI オーケストレーション方針
- `.claude/rules/*.md`: ブランチ戦略、コミット規約、等

これらもレビューの判断基準になる。

---

## 収集完了チェックリスト

PR レビュー開始前に以下が全て揃っていることを確認:

- [ ] PR メタ情報（title/body/files/commits/reviews）
- [ ] PR diff（全文、または重要箇所）
- [ ] PR 本文で参照される Issue / Epic の本文
- [ ] PR で参照される ADR / Spec の本文（ステータス含む）
- [ ] 対象ファイルの既存同類ドキュメント
- [ ] 対象領域の CLAUDE.md
- [ ] （実装 PR）既存の類似実装パターン
- [ ] 既存の CodeRabbit / 他レビュアーのコメント

### 時短パターン

ドキュメント PR で時間がない場合の最小セット:
- PR メタ + diff
- Epic の本文（Epic 備考が最も重要）
- 既存の同類ドキュメント（1〜2 個）
- 該当領域の CLAUDE.md

実装 PR で時間がない場合の最小セット:
- PR メタ + diff
- 既存の類似実装パターン（grep で数箇所）
- 該当領域の CLAUDE.md

---

## アンチパターン

- ❌ **diff だけ見て俯瞰レビュー**: 「目的達成度」「代替案」「Spec 整合」が評価できない
- ❌ **Epic 本文を読まない**: Epic 備考に書かれた設計前提（命名規則など）を見落とす
- ❌ **既存同類ドキュメントを読まない**: 責務分離の破綻・情報の二重管理を見落とす
- ❌ **既存実装パターンを grep しない**: 実装 PR で「既存パターンと違う書き方」を見落とす
- ❌ **CodeRabbit 指摘を読まない**: 指摘の二重化が発生して作成者の負担が増える
