#!/bin/bash
# 共有ライブラリ: クロスプラットフォーム timeout ラッパー。
#
# このファイルは単体実行するスクリプトではない。呼び出し元のスクリプトから
# `source` して `_timeout` 関数だけを使う。
#
# Usage（呼び出し元スクリプトの先頭付近）:
#   LIB_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
#   source "${LIB_DIR}/lib-timeout.sh"
#   _timeout 120 some-command --with args
#
# 実装: GNU timeout (Linux) → gtimeout (macOS coreutils) → perl の alarm (macOS 標準)
# の順で試す。macOS には `timeout` コマンドが標準で存在しないため、呼び出し元は
# 素の `timeout` を直接使わないこと（`command not found` で即死する）。
#
# 元々は scripts/gemini-preflight.sh に閉じて定義されていたが、Codex レビュー
# （scripts/codex-review.sh）でも同じ仕組みが必要になったため、共有ライブラリへ
# 切り出した。

# 注意: このファイルは source される側なので、`set` でシェルオプションを変更しない。
# 変更すると呼び出し元スクリプトの挙動を書き換えてしまう。

_timeout() {
  local dur="$1"; shift
  if command -v timeout >/dev/null 2>&1; then
    timeout "$dur" "$@"
  elif command -v gtimeout >/dev/null 2>&1; then
    gtimeout "$dur" "$@"
  else
    perl -e 'my $d=shift; alarm $d; exec @ARGV or die "exec failed: $!"' "$dur" "$@"
  fi
}
