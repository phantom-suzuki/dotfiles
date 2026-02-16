---
description: Go coding conventions
globs: "**/*.go"
---
- エラーは fmt.Errorf("context: %w", err) でラップ
- golangci-lint でリント（プロジェクト .golangci.yml に従う）
- テストは testify/assert、DBモックは sqlmock
- make lint && make test をコミット前に実行
- Clean Architecture の層境界を守る
