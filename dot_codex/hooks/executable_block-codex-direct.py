#!/usr/bin/env python3
"""PreToolUse hook: block direct `codex` CLI invocation in Bash.

Direct `codex ...` calls (especially the interactive REPL) tend to hang the
Bash tool. Route every Codex call through the codex:rescue plugin instead,
which wraps it in the codex-companion runtime with proper timeouts.

This hook only blocks when a *command-position* token's basename is exactly
`codex`. It deliberately does NOT match:
  - `node .../codex-companion.mjs ...`  (the plugin's own legitimate path)
  - `grep codex`, `echo codex:rescue`, `cd codex-dir`  (codex as an argument)
"""
import sys
import json
import re
import shlex
import os

# Wrapper commands that take another command as their argument. We skip past
# them (and their flags / env-assignments / numeric duration args) to reach the
# real command being invoked, e.g. `timeout 60 codex exec` -> `codex`.
WRAPPERS = {
    "env", "command", "nohup", "stdbuf", "nice", "time", "exec",
    "sudo", "xargs", "timeout", "setsid", "ionice", "doas",
}

ENV_ASSIGN = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")
DURATION = re.compile(r"^\d+[smhd]?$")
# Shell control operators that separate command segments.
SEGMENT_SPLIT = re.compile(r"\|\||&&|[;|&\n]|\$\(|\)|`")


def invokes_codex(cmd: str) -> bool:
    for seg in SEGMENT_SPLIT.split(cmd):
        seg = seg.strip()
        if not seg:
            continue
        try:
            tokens = shlex.split(seg)
        except ValueError:
            tokens = seg.split()
        i = 0
        # Skip leading env-var assignments (FOO=bar codex ...).
        while i < len(tokens) and ENV_ASSIGN.match(tokens[i]):
            i += 1
        # Skip wrapper commands and their flags / env / duration args.
        while i < len(tokens) and tokens[i] in WRAPPERS:
            i += 1
            while i < len(tokens) and (
                tokens[i].startswith("-")
                or ENV_ASSIGN.match(tokens[i])
                or DURATION.match(tokens[i])
            ):
                i += 1
        if i < len(tokens) and os.path.basename(tokens[i]) == "codex":
            return True
    return False


def main() -> None:
    try:
        data = json.load(sys.stdin)
    except Exception:
        sys.exit(0)  # unparseable input -> do not block
    if data.get("tool_name") != "Bash":
        sys.exit(0)
    cmd = (data.get("tool_input") or {}).get("command", "") or ""
    if not cmd or not invokes_codex(cmd):
        sys.exit(0)
    reason = (
        "codex CLI の直接実行はブロックされています（Bash 直叩きはハングの原因になるため）。"
        "代わりに codex:rescue プラグイン経由で Codex を呼び出してください: "
        "対話セッションなら /codex:rescue スキル、サブタスク委譲なら codex-rescue サブエージェント "
        "（内部で node codex-companion.mjs が適切なタイムアウト付きで実行します）。"
    )
    out = {
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": reason,
        }
    }
    print(json.dumps(out, ensure_ascii=False))
    sys.exit(0)


if __name__ == "__main__":
    main()
