---
name: terraform-apply-recovery
description: Terraform / Terragrunt の apply 失敗・部分成功・state ドリフトからの復旧手順を正本化したスキル。「apply が失敗した」「EntityAlreadyExists / AlreadyExists / 409」「孤児リソース」「state とのズレ」「凍結フラグを true に戻したい」「caller を re-enable したい」「module rename」「moved block」「import block」「removed block」「partial apply」「terraform state mv」「destroy -target」等の依頼時に必ず使用する。途中で失敗した apply の残骸が後で衝突する典型事故（部分成功 → 残骸放置 → 設計変更 → 再開時に EntityAlreadyExists）を防ぐためのプロセス。AWS provider を主例として記載するが、原則と判断ツリーは provider 非依存。
---

# Terraform / Terragrunt Apply Recovery

apply が失敗したとき、部分的にクラウド側に作られたリソースを放置しない。**「失敗 → 残骸放置 → 設計変更 → 再開時に衝突」** という事故が繰り返し起きる構造を断つためのプロセス。

## 起動条件

以下のいずれかに該当したら本スキルの判断ツリーに沿って進める:

- terragrunt / terraform apply が exit 1 で停止した
- `EntityAlreadyExists` / `AlreadyExists` / `409 Conflict` 等の名前衝突エラー
- `Resource ... is not in the state` / `... already managed by Terraform` 等のドリフトエラー
- caller の凍結フラグ（`enabled.<key> = false` / `exclude { if = ... }`）を `true` に戻して再有効化したい
- module rename / 内部構造変更（リソース名変更、`count → for_each` 化、resource → module 化）を行いたい
- AWS / GCP / Azure 側で「terraform 管理外のはずのリソース」を見つけた

## 基本原則

apply の途中失敗は AWS / GCP / Azure いずれの provider でも **ロールバックされない**。途中までに作成成功したリソースはそのまま残る。terraform 自身も rollback 機能を持たない。これを前提に動く。

### 原則 1: apply 失敗は「タスク終了」ではなく「タスクの途中」

失敗の瞬間からコード修正だけで再 apply するのは禁止。**残骸の所在を確認 → AWS 側 / state の整合を取り戻す → 0-diff 再 apply** までを 1 タスクで完結させる。

### 原則 2: 凍結 ≠ destroy

`enabled = false` や `exclude` で caller をスキップしても、**AWS 側の現物は削除されない**。state からの参照だけが切れる。「無いことにする」運用は孤児を生み続ける。

### 原則 3: rename / 内部構造変更時は `moved` を書く

`git mv` でファイルを動かしても terraform 視点ではリソースの logical address が切り替わるだけ。`moved {}` block / `terraform state mv` で **新旧の対応関係**を明示しないと、旧 state 行が宙に浮き、新 state は空のままで apply 時に重複 create を試行する。

---

## ステップ 1: failed apply 直後の first response

apply が失敗したらすぐに以下の手順に入る。

### 1-1. エラー分類

apply ログから以下を判定する:

| 兆候 | 分類 | 含意 |
|---|---|---|
| ログ冒頭から `Error: creating ...` | 1 件目から失敗 = 何も作られていない | state も AWS もクリーン。コード修正のみで再 apply 可 |
| 一部リソースに `Creation complete after ...` が出た **後で**別リソースが Error | **部分成功 / 残骸あり** | 後始末必須（1-2 〜 1-4） |
| `EntityAlreadyExists` / `AlreadyExists` / `409 Conflict` | 名前衝突 | 過去の残骸 or 別 stack 既存。1-2 〜 1-4 で整理 |
| `Resource ... is not in the state` / refresh 時の不整合 | state ↔ AWS ドリフト | refresh / import で同期 |
| `permission denied` / `AccessDenied` で 1 件目失敗 | 権限不足 | 残骸無し、IAM 修正のみで再 apply |
| `permission denied` で **複数 step 後**失敗 | 部分成功 + 権限不足 | 残骸あり、後始末してから IAM 修正 |

### 1-2. AWS 側の現物確認

apply ログ上で `Creation complete` が出ているリソースを抽出 → AWS API / console で実在確認する。最低でも **失敗ステップ直前まで** の作成済みリソースを全て洗う。

```bash
# 例: IAM Policy の存在確認
aws iam get-policy --policy-arn arn:aws:iam::<account>:policy/<name>

# 例: Tag-based 横断検索（Project tag 等で絞る）
aws resourcegroupstaggingapi get-resources \
  --tag-filters Key=Project,Values=<project-name>

# 例: terraform state vs AWS の差分検査
terragrunt run -- state list   # state にあるリソース
# → 各 resource を AWS API で実在確認
```

### 1-3. state との突き合わせ

| state | AWS | 状態 | 対処 |
|---|---|---|---|
| ある | ある | 整合（problem-free） | コード修正で再 apply |
| ある | 無い | state-only ghost | `terragrunt run -- state rm <addr>` |
| 無い | ある | **孤児（orphan）** | 1-4 の 3 択 |
| 無い | 無い | 何も無い | コード修正で再 apply |

### 1-4. 残骸処理 3 択

孤児（state 無し / AWS あり）を見つけたら以下から選ぶ。

| 手段 | 用途 | 主要コマンド |
|---|---|---|
| **A. AWS 手動削除** | 残骸が孤立しており再作成が安全。最速 | console / `aws <service> delete-...` 系 |
| **B. import block** | 残骸を保持して新 state に取り込みたい。ADR-008 等「全変更 CI/CD 経由」原則と整合 | `import { to = <addr>; id = "<aws-id>" }` を `.tf` に追記 → apply |
| **C. destroy -target** | state にも AWS にも存在し、両方消したい | `terragrunt run -- destroy -target=<address>` |

判断フロー:

```
孤児を発見
  ├─ 残したい？
  │    ├─ Yes → B（import block）
  │    └─ No  → A（AWS 手動削除）
  └─ state にもある？
       └─ Yes → C（destroy -target で両方）
```

#### import block 例

```hcl
# 既存 IAM Policy を新 state に取り込む
import {
  to = aws_iam_policy.composer_env_access
  id = "arn:aws:iam::448406925066:policy/wp-platform-dev-composer-env-access"
}
```

apply 後に新 state に取り込まれる。drift があれば次の plan で update が走るので diff を必ず目視。取り込みが完了したら `import {}` block は削除する PR を別途出す（保持しても害は少ないが、責務が「初回取り込み」と明確なため）。

### 1-5. 0-diff 再 apply

整理が終わったら本来の作業に戻る前に必ず:

```bash
terragrunt run -- plan
# → "No changes. Your infrastructure matches the configuration." を確認
```

これが出ない限り、まだ state と AWS が揃っていない。揃うまで 1-2 〜 1-4 を反復。

---

## ステップ 2: caller 凍結前のチェックリスト

`enabled.<key> = false` や `exclude { if = ... }` で caller を凍結する前に必ず確認:

- [ ] その caller を **過去に一度でも apply 試行したか**（git log で flag 履歴確認）
- [ ] apply 試行があった場合、AWS 側にリソースが **残っていないか** 確認（1-2 と同手順）
- [ ] 残っていれば **destroy** で空に揃える（**凍結は destroy ではない**）
- [ ] 凍結理由 + 「AWS 側に残置リソース無しを確認した」記録を caller の terragrunt.hcl コメントに残す

```bash
# 凍結直前の最終確認
terragrunt run -- plan       # 現在何があるか
terragrunt run -- destroy    # 空にする（必要に応じて -target で個別）
# その後 enabled = false を merge
```

凍結 = state からも参照しなくなる = **AWS の現物と state のズレを放置するスイッチ**。これを意識するだけで予防できる。

---

## ステップ 3: module rename / 内部構造変更

ファイル名 / module 名 / リソース名 / 反復構造（count ↔ for_each）を変えるとき、terraform から見ると **logical address が変わる** ため state mv 操作が必須。

### 使い分け表

| 手段 | 用途 | 形式 |
|---|---|---|
| `moved {}` block | logical address が変わるだけで AWS 上のリソースは同じ。**最も推奨** | terraform 1.1+ |
| `import {}` block | 既存 AWS リソースを新 state に取り込む（state に無いケース） | terraform 1.5+ |
| `removed {}` block | 旧 state から外すが AWS では destroy しない | terraform 1.7+ |
| `terraform state mv` | 命令的に state を移動 | CLI コマンド |

`moved` / `import` / `removed` block は **コードに残せて CI/CD 経由で adopt できる** のが利点。`state mv` は CLI 経由なので「全変更 CI/CD 経由」原則のあるリポでは挟みづらい。新規実装は **block ベース推奨**。

### moved block 例

```hcl
# module rename（旧 module path → 新 module path）
moved {
  from = module.composer_oidc_policy_attachment.aws_iam_policy.composer_env_access
  to   = module.composer_execution_role.aws_iam_policy.composer_env_access
}

# count → for_each 化
moved {
  from = aws_instance.web[0]
  to   = aws_instance.web["primary"]
}
```

### removed block 例

```hcl
# 旧 module を消すが AWS のリソースは別管理に移したので残す
removed {
  from = module.legacy_logging
  lifecycle {
    destroy = false
  }
}
```

### 注意点

- `moved` だけでは AWS 側の挙動は変わらない。**logical address のリラベル**だけ
- 既存 state 行と新 module の resource 構成が **1:1 対応する** ことが前提。internal layout が変わる場合は moved を複数並べる
- ファイル `git mv` だけだと state との接続が切れる。**moved block 必須**

---

## ステップ 4: 凍結フラグを true に戻すとき

`enabled.<key> = false → true` に戻す PR は以下を必須にする:

1. **plan を必ず目視**: `create` 行に既に AWS に存在するリソース名が出ていないか確認
   - 出ていれば → ステップ 1（first response）の判断ツリーへ
   - 出ていなければ → そのまま apply 可
2. plan で問題があれば **import block** を同 PR に含める or 別 PR で先に整理
3. apply 後 `plan` で **No changes** を再確認

### 凍結期間が長い caller の典型事故

```
T+0    apply 試行 → 部分成功で fail
T+0    flag = false で凍結（残骸放置）
T+N日  module rename + 内部構造変更（moved 無し）
T+M日  flag = true に戻す → apply で衝突 ← 今ここで気付く
```

このパターンを避けるには:
- 凍結時点でステップ 2 のチェックリスト
- rename 時にステップ 3 の moved block
- 解凍時にステップ 4 の plan 目視

---

## CI / 運用ガード

| 仕掛け | 目的 |
|---|---|
| 凍結 flag の ON↔OFF 切替 PR は plan 出力を PR description に貼る | レビュアーが create 行を目視できる |
| drift detection の定期実行 | 月次等で `infra-initial-deploy.yml` の `action: plan` を回し diff を Issue 化 |
| apply 失敗時の runbook 化 | failed apply に対する後処理（ステップ 1）を docs / Issue テンプレに固定 |
| 命名規則に module 名を含める | 孤児が出ても由来が辿れる（例: `<project>-<env>-<module>-<purpose>`） |

---

## アンチパターン

- ❌ apply 失敗をコード修正だけで再 apply → 半端な残骸が後で衝突
- ❌ flag を false にして「とりあえず凍結」 → AWS 残置に気付かず後で爆発
- ❌ module rename で `git mv` だけ、`moved` block 書かず → state 切断 → 再 apply で重複 create
- ❌ destroy せず flag false で「無いことにする」 → 状態と現物の食い違いを放置
- ❌ 部分成功時に `state rm` だけして AWS の現物を残す → 二重に孤児化
- ❌ EntityAlreadyExists を見て「とりあえず import」と決め打ち → drift detection せず違う設定の現物を取り込む

---

## 参考

- `~/.claude/rules/terraform-conventions.md`（規約・provider 等の不変ルール、本スキルの上位）
- ADR-008（CI/CD 経由原則）— 「全変更 CI/CD 経由」原則のため、復旧手順も極力 CI/CD で回すこと
- terraform 公式: [moved block](https://developer.hashicorp.com/terraform/language/modules/develop/refactoring) / [import block](https://developer.hashicorp.com/terraform/language/import) / [removed block](https://developer.hashicorp.com/terraform/language/resources/syntax#removing-resources)

## 改訂ログ

- v1（2026-05-09）: 初版。wp-platform Issue #461 / #461 関連 PR #573 のインシデント（composer-execution-role IAM Policy 衝突）を起点に整備。
