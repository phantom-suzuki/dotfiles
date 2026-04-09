# ADR ディレクトリ検出ロジック

## 検出順序

以下の順序でディレクトリを探索する。最初に見つかったものを採用する。

1. `docs/adr/`
2. `docs/adrs/`
3. `docs/decisions/`
4. `docs/architecture/decisions/`
5. `adr/`
6. `adrs/`
7. `decisions/`
8. サブディレクトリ内の上記パターン（例: `engineering/adrs/`）

検索は git リポジトリのルートから行う。

## テンプレート検出

ADR ディレクトリ内で以下のファイル名を探索する:

1. `template.md`
2. `adr-template.md`
3. `ADR-0000-template.md`（番号 0000 のテンプレート）
4. `000-template.md`

## 命名規則の検出

既存 ADR ファイル名のパターンを分析し、以下のいずれかに分類する:

| パターン | 正規表現 | 例 |
|----------|---------|-----|
| `ADR-NNNN` | `^ADR-(\d{4})` | `ADR-0001-use-postgresql.md` |
| `NNN-title` | `^(\d{3})-` | `001-use-postgresql.md` |
| `adr-NNN` | `^adr-(\d{3})-` | `adr-001-use-postgresql.md` |
| `NNNN-title` | `^(\d{4})-` | `0001-use-postgresql.md` |

検出できない場合（ADR が1件もない場合）のデフォルト: `ADR-NNNN` パターン（4桁ゼロ埋め）。

## 次番号の算出

既存の最大番号 + 1 を次の番号とする。
番号の欠番は埋めない（単調増加を維持する）。

## ファイル名の生成

```
{番号プレフィックス}-{タイトルのスラッグ}.md
```

タイトルのスラッグ変換ルール:
- 日本語はそのまま英語に意訳してスラッグ化する
- 小文字、ハイフン区切り
- 40文字以内に収める
- 例: 「PostgreSQL をプライマリ DB に採用」→ `use-postgresql-as-primary-db`

**生成したファイル名はユーザーに確認する。** 意訳の精度が不安定な場合があるため、提示して OK か修正かを確認してから書き出す。
