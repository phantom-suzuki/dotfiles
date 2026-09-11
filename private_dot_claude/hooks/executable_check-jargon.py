#!/usr/bin/env python3
"""Stop hook: 直前の応答に内輪語が混ざっていないか点検し、当たった語を記録する。

非ブロッキング設計: 常に exit 0 で返し、応答を差し戻さない。
まず誤検知の具合を観測する段階のため、記録だけを取る（2026-09-11 開始）。
止める設定に上げるかは、~/.claude/state/jargon-hits.jsonl の中身を見てから決める。

検出リストの正本は ~/.claude/docs/glossary/jargon.md の表。
2 列目がバッククォートで囲まれた正規表現の行だけを読む。`—` の行は検出しない。
"""
import sys
import os
import re
import json
import datetime
import pathlib

# 表の行から「| 内輪語 | `パターン` | 標準語 | 補足 |」を取り出す
ROW = re.compile(r"^\|([^|]+)\|([^|]+)\|([^|]+)\|([^|]*)\|\s*$")
BACKTICKED = re.compile(r"^`([^`]+)`$")

FENCE = re.compile(r"```.*?```", re.S)
INLINE_CODE = re.compile(r"`[^`\n]*`")
QUOTE_LINE = re.compile(r"^\s*>.*$", re.M)
URL = re.compile(r"https?://\S+")
PATH_LIKE = re.compile(r"[~./][\w./-]*[\w/-]")


def load_patterns(glossary):
    """jargon.md から (内輪語, コンパイル済みパターン, 標準語) を読む。"""
    out = []
    try:
        text = glossary.read_text(encoding="utf-8")
    except Exception:
        return out
    for line in text.splitlines():
        m = ROW.match(line)
        if not m:
            continue
        term, pat_cell, standard = (m.group(i).strip() for i in (1, 2, 3))
        b = BACKTICKED.match(pat_cell)
        if not b:
            continue
        pattern = b.group(1)
        if pattern in ("—", "-", ""):
            continue
        try:
            out.append((term, re.compile(pattern), standard))
        except re.error:
            continue
    return out


def last_assistant_text(transcript):
    """transcript の最後の assistant メッセージから、ユーザー向けの本文だけを返す。"""
    try:
        lines = pathlib.Path(transcript).read_text(encoding="utf-8").splitlines()
    except Exception:
        return ""
    for line in reversed(lines):
        if '"assistant"' not in line:
            continue
        try:
            rec = json.loads(line)
        except Exception:
            continue
        if rec.get("type") != "assistant":
            continue
        content = (rec.get("message") or {}).get("content")
        if not isinstance(content, list):
            continue
        parts = [c.get("text", "") for c in content
                 if isinstance(c, dict) and c.get("type") == "text"]
        if parts:
            return "\n".join(parts)
    return ""


def strip_noise(text):
    """コード・引用・URL・パスを落とす。これらの中の語は検出対象にしない。"""
    text = FENCE.sub(" ", text)
    text = INLINE_CODE.sub(" ", text)
    text = QUOTE_LINE.sub(" ", text)
    text = URL.sub(" ", text)
    text = PATH_LIKE.sub(" ", text)
    return text


def main():
    try:
        data = json.load(sys.stdin)
    except Exception:
        sys.exit(0)

    # 差し戻しの連鎖を防ぐ。記録だけの段階でも作法として守る。
    if data.get("stop_hook_active"):
        sys.exit(0)

    transcript = data.get("transcript_path", "")
    if not transcript:
        sys.exit(0)

    home = pathlib.Path.home()
    glossary = home / ".claude" / "docs" / "glossary" / "jargon.md"
    patterns = load_patterns(glossary)
    if not patterns:
        sys.exit(0)

    text = last_assistant_text(transcript)
    if not text:
        sys.exit(0)

    # 用語集そのものを編集した回は、語が本文に出るのが正常なので数えない。
    if "glossary" in text or "内輪語" in text:
        sys.exit(0)

    body = strip_noise(text)
    hits = []
    for term, pat, standard in patterns:
        found = pat.findall(body)
        if found:
            hits.append({"term": term, "standard": standard, "count": len(found)})

    if not hits:
        sys.exit(0)

    state_dir = home / ".claude" / "state"
    try:
        state_dir.mkdir(parents=True, exist_ok=True)
        rec = {
            "at": datetime.datetime.now().astimezone().isoformat(timespec="seconds"),
            "session_id": str(data.get("session_id") or ""),
            "cwd": data.get("cwd", os.getcwd()),
            "hits": hits,
        }
        with (state_dir / "jargon-hits.jsonl").open("a", encoding="utf-8") as f:
            f.write(json.dumps(rec, ensure_ascii=False) + "\n")
    except Exception:
        pass

    sys.exit(0)


if __name__ == "__main__":
    main()
