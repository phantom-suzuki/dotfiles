---
description: Terraform/Terragrunt conventions
globs: "**/*.tf,**/*.hcl,**/terragrunt.hcl"
---
- Terragrunt で環境管理（_envcommon/ に共通、env/service/ にオーバーライド）
- SSM Parameter ベースのサービスディスカバリ
- petoju/mysql プロバイダを使用（hashicorp/mysql は非推奨）
- plan 出力を必ず確認してから apply
- actionlint で GitHub Actions ワークフローを検証
