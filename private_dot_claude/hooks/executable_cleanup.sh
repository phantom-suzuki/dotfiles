#!/usr/bin/env bash
# Claude Code hook: セッション残骸の自動クリーンアップ
# Stop イベント時に実行。3日以上古いファイルを削除。
# 3日閾値 = Agent Teams セッションが数日跨ぐケースを保護

set -euo pipefail

CLAUDE_DIR="${HOME}/.claude"
RETENTION_DAYS=3

# 3日以上古いファイルを削除（長期セッションの保護）
find "${CLAUDE_DIR}/todos" -type f -name "*.json" -mtime +${RETENTION_DAYS} -delete 2>/dev/null || true
find "${CLAUDE_DIR}/shell-snapshots" -type f -name "*.sh" -mtime +${RETENTION_DAYS} -delete 2>/dev/null || true
