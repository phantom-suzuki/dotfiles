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

# PreCompact フックが残す compaction スナップショット（state/compact-snapshot-*.md）の蓄積防止。
# セッションごとに 1 ファイル増え、自動 retention が無いため放置すると無限蓄積する。
find "${CLAUDE_DIR}/state" -type f -name "compact-snapshot-*.md" -mtime +${RETENTION_DAYS} -delete 2>/dev/null || true

# Codex CLI トレースログ（logs_*.sqlite）の肥大防止
# Codex は自動 retention を持たず logs テーブルに無限追記する（実測 ~48MB/日）。
# RETENTION_DAYS より古い行を削除し、Codex 非走行時かつ 50MB 超のときだけ VACUUM で実圧縮する。
#   - DELETE: WAL + busy_timeout により走行中でも整合性が保たれる（best-effort、失敗は無視）
#   - VACUUM: 排他ロックが必要なため app-server 非走行時のみ。毎回の無駄を避け 50MB 超で限定実行
#   - logs_* ワイルドカード: スキーマ版数による filename 変更（logs_2 → logs_3 …）に追従
#   - ~/.codex-work: codex-account スキルの work アカウント CODEX_HOME も対象に含める
if command -v sqlite3 >/dev/null 2>&1; then
  codex_log_cutoff=$(( $(date +%s) - RETENTION_DAYS * 86400 ))
  codex_running=1
  pgrep -f 'codex app-server' >/dev/null 2>&1 || codex_running=0
  for codex_home in "${HOME}/.codex" "${HOME}/.codex-work"; do
    [ -d "${codex_home}" ] || continue
    for log_db in "${codex_home}"/logs_*.sqlite; do
      [ -f "${log_db}" ] || continue
      sqlite3 "${log_db}" "PRAGMA busy_timeout=3000; DELETE FROM logs WHERE ts < ${codex_log_cutoff};" >/dev/null 2>&1 || true
      if [ "${codex_running}" -eq 0 ]; then
        db_size=$(stat -f%z "${log_db}" 2>/dev/null || echo 0)
        if [ "${db_size}" -gt 52428800 ]; then
          sqlite3 "${log_db}" "PRAGMA busy_timeout=3000; VACUUM;" >/dev/null 2>&1 || true
        fi
      fi
    done
  done
fi
