#!/usr/bin/env python3
"""PreCompact hook: compaction 直前に機械的なセッション状態をスナップショットする。

非ブロッキング設計: 常に exit 0 で返し、compaction を止めない（snapshot のみ）。
command フックのため意味的状態（確定方針・未解決点）の自動抽出はできない。
ここで取れるのは git 差分・branch・直近ユーザー発言などの機械的事実に限る。
出力先は ~/.claude/state/compact-snapshot-<session_id>.md（リポジトリを汚さない）。
PostCompact フックがこのファイルを読んで再注入する。
"""
import sys
import os
import json
import subprocess
import datetime
import pathlib


def main():
    try:
        data = json.load(sys.stdin)
    except Exception:
        data = {}

    session_id = data.get("session_id", "unknown")
    transcript = data.get("transcript_path", "")
    cwd = data.get("cwd", os.getcwd())
    trigger = data.get("trigger", "?")

    state_dir = pathlib.Path.home() / ".claude" / "state"
    try:
        state_dir.mkdir(parents=True, exist_ok=True)
    except Exception:
        sys.exit(0)
    out = state_dir / f"compact-snapshot-{session_id}.md"

    lines = []
    ts = datetime.datetime.now().astimezone().isoformat(timespec="seconds")
    lines.append(f"# Compact snapshot (trigger={trigger}) {ts}")
    lines.append(f"- cwd: {cwd}")

    def git(*args):
        try:
            r = subprocess.run(
                ["git", "-C", cwd, *args],
                capture_output=True, text=True, timeout=5,
            )
            return r.stdout.strip()
        except Exception:
            return ""

    branch = git("rev-parse", "--abbrev-ref", "HEAD")
    if branch:
        lines.append(f"- branch: {branch}")
        status = git("status", "--porcelain")
        if status:
            lines.append("- changed files:")
            for l in status.splitlines()[:50]:
                lines.append(f"    {l}")
        else:
            lines.append("- changed files: (clean)")

    # 直近ユーザー発言の抽出（best-effort: transcript JSONL のスキーマ差異に耐えるよう緩く読む）
    user_msgs = []
    try:
        with open(transcript, "r", encoding="utf-8", errors="ignore") as f:
            for line in f:
                try:
                    ev = json.loads(line)
                except Exception:
                    continue
                msg = ev.get("message") if isinstance(ev, dict) else None
                role = None
                content = None
                if isinstance(msg, dict):
                    role = msg.get("role")
                    content = msg.get("content")
                if role != "user" and ev.get("type") != "user":
                    continue
                text = ""
                if isinstance(content, str):
                    text = content
                elif isinstance(content, list):
                    text = " ".join(
                        c.get("text", "")
                        for c in content
                        if isinstance(c, dict) and c.get("type") == "text"
                    )
                text = text.strip().replace("\n", " ")
                if text:
                    user_msgs.append(text[:280])
    except Exception:
        pass
    if user_msgs:
        lines.append("- recent user messages (most recent last):")
        for m in user_msgs[-6:]:
            lines.append(f"    - {m}")

    try:
        out.write_text("\n".join(lines) + "\n", encoding="utf-8")
    except Exception:
        pass
    sys.exit(0)


if __name__ == "__main__":
    main()
