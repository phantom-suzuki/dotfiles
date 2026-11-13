#!/usr/bin/env python3
"""PostToolUse フック: `gh pr merge` の後に、マージしたブランチの worktree が残っていれば片付けを促す。

2026-11 に、16 リポジトリで 251 個の worktree が残り、内蔵ディスクの空きが 4 GB まで減った。
マージした直後が、その worktree を消してよいと分かる唯一の時点である。ここで促す。

このフックは促すだけで、何も消さない。消すのは Claude が変更の無いことを確かめてから行う。
取りこぼし（手動のマージ・中断したセッション）は、週 1 回の worktree-sweep が拾う。
"""
import json
import re
import shlex
import subprocess
import sys

# 値を取るオプション。次のトークンを PR の指定と取り違えないために列挙する。
FLAGS_WITH_VALUE = {
    "-b", "--body", "-F", "--body-file", "-t", "--subject",
    "-A", "--author-email", "--match-head-commit", "-R", "--repo",
}
SEPARATORS = {"&&", "||", ";", "|", "&"}


def parse_merge(command):
    """コマンド文字列から `gh pr merge` の PR 指定と --repo を取り出す。無ければ None を返す。"""
    try:
        tokens = shlex.split(command, posix=True)
    except ValueError:
        return None
    for i in range(len(tokens) - 2):
        if tokens[i].endswith("gh") and tokens[i + 1] == "pr" and tokens[i + 2] == "merge":
            target, repo = None, None
            j = i + 3
            while j < len(tokens) and tokens[j] not in SEPARATORS:
                tok = tokens[j]
                if tok in ("-R", "--repo") and j + 1 < len(tokens):
                    repo = tokens[j + 1]
                    j += 2
                    continue
                if tok.startswith("--repo="):
                    repo = tok.split("=", 1)[1]
                elif tok in FLAGS_WITH_VALUE:
                    j += 2
                    continue
                elif not tok.startswith("-") and target is None:
                    target = tok
                j += 1
            return target, repo
    return None


def run(args, cwd):
    try:
        r = subprocess.run(args, cwd=cwd, capture_output=True, text=True, timeout=15)
    except (OSError, subprocess.TimeoutExpired):
        return None
    return r.stdout if r.returncode == 0 else None


def find_worktree(cwd, branch):
    """branch をチェックアウトしている worktree のパスを返す。リポジトリ本体（先頭）は対象にしない。"""
    out = run(["git", "worktree", "list", "--porcelain"], cwd)
    if not out:
        return None
    blocks = [b for b in out.strip().split("\n\n") if b.strip()]
    for block in blocks[1:]:
        path = None
        for line in block.splitlines():
            if line.startswith("worktree "):
                path = line[len("worktree "):]
            elif line == f"branch refs/heads/{branch}":
                return path
    return None


def main():
    try:
        data = json.load(sys.stdin)
    except ValueError:
        return
    if data.get("tool_name") != "Bash":
        return
    command = (data.get("tool_input") or {}).get("command", "")
    if not re.search(r"\bgh\s+pr\s+merge\b", command):
        return
    parsed = parse_merge(command)
    if parsed is None:
        return
    target, repo = parsed
    cwd = data.get("cwd") or None

    view = ["gh", "pr", "view"]
    if target:
        view.append(target)
    if repo:
        view += ["--repo", repo]
    view += ["--json", "state,headRefName,number"]
    out = run(view, cwd)
    if not out:
        return
    try:
        pr = json.loads(out)
    except ValueError:
        return
    # --auto を付けたマージなど、まだマージされていない場合は何も言わない
    if pr.get("state") != "MERGED":
        return

    path = find_worktree(cwd, pr.get("headRefName", ""))
    if not path:
        return

    message = (
        f"PR #{pr.get('number')} のブランチ {pr.get('headRefName')} の worktree が残っている: {path}\n"
        "この応答の中で片付ける。手順: (1) `git -C <path> status --porcelain` が空であることを確かめる。"
        " (2) 空なら、worktree の外から `git worktree remove <path>` を実行する（--force は使わない）。"
        " (3) 変更が残っている、または消せなかった場合は、消さずに理由をユーザーへ報告する。"
    )
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PostToolUse",
            "additionalContext": message,
        }
    }, ensure_ascii=False))


if __name__ == "__main__":
    main()
