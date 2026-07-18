#!/usr/bin/env python3
"""Regression tests for the block-codex-direct PreToolUse hook.

Run with:  python3 tests/test_block_codex_direct.py

Loads the hook module by file path (its filename is hyphenated and prefixed
with chezmoi's `executable_` attribute prefix) and exercises `invokes_codex`
against a table of commands that must / must not be blocked.
"""
import importlib.util
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
HOOK_PATH = os.path.join(
    HERE, "..", "private_dot_claude", "hooks", "executable_block-codex-direct.py"
)

spec = importlib.util.spec_from_file_location("block_codex_direct", HOOK_PATH)
hook = importlib.util.module_from_spec(spec)
spec.loader.exec_module(hook)

# Each case: (label, command, should_block)
CASES = [
    # --- MUST BLOCK: genuine direct codex invocations -------------------------
    ("direct exec", "codex exec 'do the thing'", True),
    ("timeout wrapper", "timeout 60 codex exec", True),
    ("env prefix", "FOO=1 codex", True),
    ("env-only prefix", "CODEX_HOME=/x codex exec", True),
    ("chained after &&", "echo x && codex", True),
    ("chained after ;", "echo x; codex exec", True),
    ("chained after |", "echo x | codex", True),
    ("absolute path", "/usr/local/bin/codex", True),
    ("command sub $()", "echo $(codex exec)", True),
    ("command sub inside dquotes", 'echo "$(codex exec)"', True),
    ("backtick sub", "echo `codex exec`", True),
    ("quoted command name", '"codex" exec', True),
    ("env wrapper word", "env codex exec", True),
    ("nested in subshell close", "(cd /tmp && codex)", True),
    ("chained after &&, spaced", "cat foo && codex exec", True),
    # --- MUST BLOCK: obfuscated / regression cases found in security review ---
    ("split by empty dquotes", 'co"dex" exec', True),
    ("split by backslash escapes", "co\\d\\ex exec", True),
    ("fake heredoc in comment", "# <<STOP\ncodex exec", True),
    ("unclosed quote in comment", '# "\ncodex exec', True),
    ("quoted heredoc delimiter word", 'cat <<E"OF"\nbody\nEOF\ncodex exec', True),
    ("unterminated heredoc keeps body", "cat <<EOF\ncodex exec", True),
    ("arithmetic left shift not heredoc", "n=$((1 << 2))\ncodex exec", True),
    ("multiline quote fake heredoc", 'x="\n<<EOF"\ncodex exec\nEOF', True),
    ("escaped quote in heredoc delim", 'cat <<"E\\"OF"\nbody\nE"OF\ncodex exec', True),
    ("ansi-c quoted heredoc delim", "cat <<$'EOF'\nbody\nEOF\ncodex exec\n$EOF", True),
    ("locale quoted heredoc delim", 'cat <<$"EOF"\nbody\nEOF\ncodex exec\n$EOF', True),
    ("backslash non-special in dquote delim", 'cat <<"E\\qOF"\nbody\nE\\qOF\ncodex exec', True),
    ("param expansion << not heredoc", "x=${x//<<x/Y}\ncodex exec\nx/Y}", True),
    ("ansi-c escape in heredoc delim", "cat <<$'E\\tOF'\nE\tOF\ncodex exec\nE\\tOF", True),
    ("line continuation before codex", "echo x | \\\ncodex exec", True),
    ("line continuation within word", "co\\\ndex exec", True),
    ("line continuation in heredoc delim", "cat <<EO\\\nF\nEOF\ncodex exec", True),
    ("quoted env value then codex", 'FOO="a b" codex exec', True),
    ("env wrapper quoted value", "env FOO='a b' codex exec", True),
    ("command sub heredoc delim", "cat <<$(printf EOF)\n$(printf EOF)\ncodex exec\n$(printf EOF)", True),
    ("trailing comment same line", "ls foo # codex exec", False),
    # real arithmetic + a real heredoc body must still be handled correctly
    ("arithmetic then heredoc body", "n=$((1 << 2)); cat <<EOF\ncodex exec\nEOF", False),
    # --- MUST NOT BLOCK: false positives the old regex produced ---------------
    ("grep arg", "grep codex file.txt", False),
    ("echo substring in dquotes", 'echo "codex exec is blocked"', False),
    ("companion mjs path", "node /p/codex-companion.mjs run", False),
    ("git commit msg with ; codex", 'git commit -m "fix: ...; codex 連携を修正"', False),
    ("review script exception", "bash ~/.claude/skills/self-review/scripts/codex-review.sh", False),
    ("cd into codex dir", "cd codex-work && ls", False),
    ("variable expansion", "echo ${codex}", False),
    ("codex as filename arg", "cat codex.log", False),
    ("single-quoted substring", "echo 'run codex exec here'", False),
    (
        "heredoc body (unquoted delim)",
        "cat <<EOF\ncodex exec should be ignored\nmore text\nEOF",
        False,
    ),
    (
        "heredoc body (quoted delim)",
        "cat <<'END'\ncodex exec ignored\nEND",
        False,
    ),
    (
        "heredoc dash delim with tabs",
        "cat <<-EOF\n\tcodex exec ignored\n\tEOF",
        False,
    ),
    (
        "heredoc then real command after",
        "cat <<EOF > f\ncodex line ignored\nEOF\necho done",
        False,
    ),
    (
        "gh body-file heredoc with codex text",
        "gh issue comment 1 -F - <<'MSG'\nWe block codex exec here.\nMSG",
        False,
    ),
]


def main() -> int:
    failures = []
    for label, cmd, expected in CASES:
        got = hook.invokes_codex(cmd)
        status = "ok " if got == expected else "FAIL"
        verdict = "BLOCK" if got else "allow"
        want = "BLOCK" if expected else "allow"
        print(f"[{status}] {label:38s} got={verdict:5s} want={want}")
        if got != expected:
            failures.append((label, cmd, expected, got))

    print()
    total = len(CASES)
    passed = total - len(failures)
    print(f"{passed}/{total} passed")
    if failures:
        print("\nFAILURES:")
        for label, cmd, expected, got in failures:
            print(f"  - {label}: want={expected} got={got}\n      cmd={cmd!r}")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
