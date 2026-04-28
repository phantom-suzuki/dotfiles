---
description: Terraform/Terragrunt conventions
globs: "**/*.tf,**/*.hcl,**/terragrunt.hcl"
---
- Terragrunt で環境管理（_envcommon/ に共通、env/service/ にオーバーライド）
- SSM Parameter ベースのサービスディスカバリ
- petoju/mysql プロバイダを使用（hashicorp/mysql は非推奨）
- plan 出力を必ず確認してから apply
- actionlint で GitHub Actions ワークフローを検証
- `terraform init` は caller (terragrunt) ディレクトリでのみ実行する。module ディレクトリで init すると `.terraform/` provider バイナリが commit に混入するリスク
- module 単独で validate したい場合は `terraform init -backend=false -input=false` 後に `rm -rf .terraform` で artifact 除去
- caller の `.terraform.lock.hcl` は commit 推奨（provider バージョン pinning）。module ディレクトリの lock file は不要、`.gitignore` で除外
