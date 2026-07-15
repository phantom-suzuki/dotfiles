#!/usr/bin/env bash
# 指定 Markdown 内の全 mermaid フェンスブロックを抽出し、mermaid.parse() で構文検証する。
# usage: check-mermaid.sh <markdown-file> [workdir]
#   workdir 省略時は mktemp -d 配下に検証環境を作る（固定パスの使い回しはしない）。
#   終了コード: 0 = 全 PASS または mermaid ブロックなし / 1 = FAIL あり
set -euo pipefail

DOC="${1:?usage: check-mermaid.sh <markdown-file> [workdir]}"
DOC="$(cd "$(dirname "$DOC")" && pwd)/$(basename "$DOC")"
WORKDIR="${2:-$(mktemp -d)/mmcheck}"

mkdir -p "$WORKDIR"
cd "$WORKDIR"

if [ ! -d node_modules/mermaid ]; then
  npm init -y >/dev/null 2>&1
  npm install mermaid@11 jsdom --no-audit --no-fund >/dev/null 2>&1
fi

cat > check.mjs <<'EOF'
import { JSDOM } from 'jsdom';
import { readFileSync } from 'fs';
const dom = new JSDOM('<!DOCTYPE html><body></body>', { pretendToBeVisual: true });
global.window = dom.window; global.document = dom.window.document;
const mermaid = (await import('mermaid')).default;
mermaid.initialize({ startOnLoad: false });
const def = readFileSync(process.argv[2], 'utf8');
try { await mermaid.parse(def); console.log('PASS: ' + process.argv[2]); }
catch (e) { console.log('FAIL: ' + process.argv[2] + ' : ' + String(e.message || e).split('\n').slice(0,3).join(' | ')); process.exit(1); }
EOF

rm -f block*.mmd
awk '/^```mermaid/{f=1;n++;next} /^```/{if(f){f=0}} f{print > ("block" n ".mmd")}' "$DOC"

shopt -s nullglob
blocks=(block*.mmd)
if [ ${#blocks[@]} -eq 0 ]; then
  echo "NO_MERMAID_BLOCKS: $DOC"
  exit 0
fi

fail=0
for b in "${blocks[@]}"; do
  node check.mjs "$b" || fail=1
done
exit $fail
