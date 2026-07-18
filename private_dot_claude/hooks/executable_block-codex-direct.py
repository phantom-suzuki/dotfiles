#!/usr/bin/env python3
"""PreToolUse hook: block direct `codex` CLI invocation in Bash.

Direct `codex ...` calls (especially the interactive REPL) tend to hang the
Bash tool. Route every Codex call through the codex:rescue plugin instead,
which wraps it in the codex-companion runtime with proper timeouts.

This hook only blocks when a *command-position* token's basename is exactly
`codex`. It deliberately does NOT match:
  - `node .../codex-companion.mjs ...`  (the plugin's own legitimate path)
  - `grep codex`, `echo codex:rescue`, `cd codex-dir`  (codex as an argument)
  - `codex` appearing inside a quoted string   (e.g. `echo "codex exec ..."`)
  - `codex` lines inside a here-document body   (e.g. `cat <<EOF ... codex`)
  - `bash .../codex-review.sh`   (a script file whose name merely contains codex)

The segmentation is quote-, comment-, and heredoc-aware: backslash-newline line
continuations are joined first, `#` comments are removed, here-document bodies
are stripped, and the remainder is scanned character by character while tracking
single/double quotes, `$((…))` arithmetic and `${…}` expansions. This avoids the
false positives that a naive regex split produced (splitting inside quotes /
heredoc bodies), while still catching command substitutions (`$(codex …)` /
backticks) and obfuscated forms (`co"dex" exec`) as — or better than — before.

This is a convenience guard against the assistant accidentally hanging the Bash
tool on a direct `codex` call, not an adversarial sandbox. It targets realistic
commands; a few pre-existing false negatives are intentionally out of scope
(they never occur in real usage and predate this parser):
  - a redirection glued to the command name (`codex>/dev/null`);
  - wrapper options that take a separate value word (`sudo -u root codex`);
  - process substitution / compound command substitution (`cat <(codex …)`,
    `$( { codex; } )`);
  - a `<<` used as a left shift inside a *bare* array subscript written with
    spaces (`a[1 << EOF ]`), or a `$[ … ]` arithmetic expansion split across
    lines — single-line `$(( … ))` / `$[ … ]` arithmetic is handled, but a bare
    `a[ … ]` is left untracked (to avoid a glob `[` leaking state) and `$[ … ]`
    is only consumed within the line it opens on.
`<<` inside single-line `$(( … ))` / `$[ … ]` arithmetic and `${ … }` expansions
is read as a left shift, not a heredoc. Other mis-parses fall back to an
untrusted delimiter whose body is scanned line by line rather than dropped, so a
hidden `codex` still blocks.
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
# A here-doc delimiter we are confident we parsed correctly and can drop the
# body of silently. Real delimiters are plain words (EOF, END, MSG, PYEOF,
# _EOF_, ...). A `<<` mis-read inside `$[ … ]` / an array subscript / an exotic
# quoted form yields a "delimiter" with other characters (`]`, `=`, `/`, `}`,
# `"`, whitespace, …); those are treated as untrusted and their body is scanned
# line by line so a hidden `codex` can never slip through.
SIMPLE_DELIM = re.compile(r"^[A-Za-z0-9_.-]+$")
HEX_DIGITS = "0123456789abcdefABCDEF"
# Single-char ANSI-C escapes ($'...'); bash keeps the backslash for anything not
# listed here (e.g. $'\z' -> \z).
ANSI_C_ESCAPES = {
    "a": "\a", "b": "\b", "e": "\x1b", "E": "\x1b", "f": "\f",
    "n": "\n", "r": "\r", "t": "\t", "v": "\v", "\\": "\\",
    "'": "'", '"': '"', "?": "?",
}


def join_continuations(cmd: str) -> str:
    """Remove `\\`-newline line continuations, as bash does before tokenizing.

    Inside single quotes a backslash-newline is literal and kept; everywhere else
    (unquoted or inside double quotes) it is removed, joining the two lines. This
    must run first: `echo x | \\<nl>codex` and `cat <<EO\\<nl>F` both hinge on the
    join to be recognized correctly.
    """
    out = []
    i, n = 0, len(cmd)
    quote = None
    while i < n:
        c = cmd[i]
        if quote == "'":
            out.append(c)
            if c == "'":
                quote = None
            i += 1
            continue
        if c == "\\" and i + 1 < n and cmd[i + 1] == "\n":
            i += 2  # line continuation removed
            continue
        if c == "\\" and i + 1 < n:
            out.append(c)
            out.append(cmd[i + 1])
            i += 2
            continue
        if c == "'" and quote != '"':
            quote = "'"
            out.append(c)
            i += 1
            continue
        if c == '"':
            quote = None if quote == '"' else '"'
            out.append(c)
            i += 1
            continue
        out.append(c)
        i += 1
    return "".join(out)


def _read_heredoc_delim(line, j, out):
    """Read a here-doc delimiter word starting at `line[j]`, applying bash's
    quote removal. Appends the consumed source to `out` and returns
    `(delimiter, next_index)`.

    bash removes quoting from the delimiter word, so `<<EOF`, `<<'EOF'`,
    `<<"EOF"`, `<<E"OF"`, `<<E\\OF`, `<<$'EOF'` and `<<$"EOF"` all terminate on
    the line `EOF`. `$'...'` additionally expands ANSI-C escapes (`$'E\\tOF'`
    terminates on `E<TAB>OF`). Getting this wrong would let us match the wrong
    line and drop an executable command as here-doc body.
    """
    n = len(line)
    dchars = []
    while j < n:
        ch = line[j]
        if ch == "$" and j + 1 < n and line[j + 1] == "(":
            # $(...) is not expanded in a delimiter word: the literal text is the
            # terminator (`<<$(printf EOF)` terminates on the line `$(printf EOF)`).
            start = j
            j += 1
            depth = 0
            while j < n:
                if line[j] == "(":
                    depth += 1
                elif line[j] == ")":
                    depth -= 1
                    if depth == 0:
                        j += 1
                        break
                j += 1
            text = line[start:j]
            dchars.append(text)
            out.append(text)
            continue
        if ch == "`":  # backtick substitution in a delimiter: also literal text
            start = j
            j += 1
            while j < n and line[j] != "`":
                j += 1
            if j < n:
                j += 1
            text = line[start:j]
            dchars.append(text)
            out.append(text)
            continue
        if ch == "$" and j + 1 < n and line[j + 1] == "'":
            # $'...' ANSI-C quoting: strip the $, expand escapes.
            out.append("$'")
            j += 2
            while j < n and line[j] != "'":
                if line[j] == "\\" and j + 1 < n:
                    out.append(line[j])
                    e = line[j + 1]
                    if e in ANSI_C_ESCAPES:
                        dchars.append(ANSI_C_ESCAPES[e])
                        out.append(e)
                        j += 2
                    elif e == "x":
                        out.append(e)
                        k, hexs = j + 2, ""
                        while k < n and len(hexs) < 2 and line[k] in HEX_DIGITS:
                            hexs += line[k]
                            out.append(line[k])
                            k += 1
                        dchars.append(chr(int(hexs, 16)) if hexs else "x")
                        j = k
                    elif e in "01234567":
                        k, octs = j + 1, ""
                        while k < n and len(octs) < 3 and line[k] in "01234567":
                            octs += line[k]
                            out.append(line[k])
                            k += 1
                        dchars.append(chr(int(octs, 8) & 0xFF))
                        j = k
                    else:  # unrecognized escape: bash keeps the backslash
                        dchars.append("\\")
                        dchars.append(e)
                        out.append(e)
                        j += 2
                else:
                    dchars.append(line[j])
                    out.append(line[j])
                    j += 1
            if j < n:
                out.append(line[j])
                j += 1
        elif ch == "$" and j + 1 < n and line[j + 1] == '"':
            out.append("$")  # $"..." locale quoting: strip the $, read as "..."
            j += 1
        elif ch == "'":  # single quotes: everything literal
            out.append(ch)
            j += 1
            while j < n and line[j] != "'":
                dchars.append(line[j])
                out.append(line[j])
                j += 1
            if j < n:
                out.append(line[j])
                j += 1
        elif ch == '"':  # double quotes: \ escapes only " \ $ `
            out.append(ch)
            j += 1
            while j < n and line[j] != '"':
                if line[j] == "\\" and j + 1 < n and line[j + 1] in '"\\$`':
                    dchars.append(line[j + 1])
                    out.append(line[j])
                    out.append(line[j + 1])
                    j += 2
                    continue
                dchars.append(line[j])
                out.append(line[j])
                j += 1
            if j < n:
                out.append(line[j])
                j += 1
        elif ch == "\\":  # unquoted backslash escapes the next char
            out.append(ch)
            if j + 1 < n:
                dchars.append(line[j + 1])
                out.append(line[j + 1])
                j += 2
            else:
                j += 1
        elif ch.isspace() or ch in ";|&<>()":
            break
        else:
            dchars.append(ch)
            out.append(ch)
            j += 1
    return "".join(dchars), j


def _scan_line(line, quote, arith, brace):
    """Scan one line, carrying quote / arithmetic / `${}` state across lines.

    Returns `(stripped, delims, quote, arith, brace)` where `stripped`
    is the line with any trailing `#` comment removed and `delims` is the list of
    `(delimiter, dashed)` here-document operators that open on this line.

    Each delim is `(delimiter, dashed, trusted)`; `trusted` is False when the
    parsed delimiter does not look like a real one (see SIMPLE_DELIM), which
    signals the caller to scan the body rather than drop it blindly.

    A `<<` counts as a here-document operator only when it is unquoted, is a run
    of exactly two `<` (not the here-string `<<<`), and is not inside `$(( … ))`
    arithmetic (a left shift) or a `${...}` parameter expansion (`${x//<<x/Y}`).
    Deprecated `$[ … ]` arithmetic is consumed inline where it opens. Quote /
    arithmetic / brace state carries across lines so a `<<` that merely appears
    inside a multi-line quoted string or expansion is not read as a bogus heredoc
    that would swallow the following command.
    """
    out = []
    delims = []
    i, n = 0, len(line)
    at_word_start = quote is None

    while i < n:
        c = line[i]
        if quote == "'":
            out.append(c)
            if c == "'":
                quote = None
            i += 1
            continue
        if quote == '"':
            if c == "\\" and i + 1 < n:
                out.append(c)
                out.append(line[i + 1])
                i += 2
                continue
            out.append(c)
            if c == '"':
                quote = None
            i += 1
            continue

        # Unquoted.
        if c == "\\":
            out.append(c)
            if i + 1 < n:
                out.append(line[i + 1])
                i += 2
            else:
                i += 1
            at_word_start = False
            continue
        if c == "#" and at_word_start:
            break  # rest of the line is a comment
        if c == "'":
            quote = "'"
            out.append(c)
            at_word_start = False
            i += 1
            continue
        if c == '"':
            quote = '"'
            out.append(c)
            at_word_start = False
            i += 1
            continue
        if c == "$" and line[i + 1 : i + 3] == "((":
            arith += 1
            out.append("$((")
            i += 3
            at_word_start = False
            continue
        if c == "$" and i + 1 < n and line[i + 1] == "{":
            brace += 1
            out.append("${")
            i += 2
            at_word_start = False
            continue
        if c == "$" and i + 1 < n and line[i + 1] == "[":
            # $[…] deprecated arithmetic: consume the whole balanced region in
            # one step (matching nested `[]`) so an inner `<<` is never read as a
            # heredoc. Reading it inline avoids carrying an ambiguous bracket
            # depth across lines (a stray glob `[` must not suppress a later
            # heredoc).
            out.append("$[")
            i += 2
            depth = 1
            while i < n and depth > 0:
                if line[i] == "[":
                    depth += 1
                elif line[i] == "]":
                    depth -= 1
                out.append(line[i])
                i += 1
            at_word_start = False
            continue
        if c == "(" and i + 1 < n and line[i + 1] == "(":
            arith += 1
            out.append("((")
            i += 2
            at_word_start = False
            continue
        if c == ")" and i + 1 < n and line[i + 1] == ")" and arith > 0:
            arith -= 1
            out.append("))")
            i += 2
            at_word_start = False
            continue
        if c == "}" and brace > 0:
            brace -= 1
            out.append("}")
            i += 1
            at_word_start = False
            continue
        if c == "<" and i + 1 < n and line[i + 1] == "<":
            # Consume the whole run of `<` in one step so that `<<<` (a here-
            # string) is never re-examined one character at a time and mistaken
            # for `<` followed by a `<<` heredoc. Only a run of exactly two is a
            # heredoc operator.
            run = 2
            while i + run < n and line[i + run] == "<":
                run += 1
            if run != 2:  # here-string `<<<` (or longer): not a heredoc
                out.append("<" * run)
                i += run
                at_word_start = False
                continue
            out.append("<<")
            j = i + 2
            # `<<` in arithmetic (left shift) or a `${}` expansion is not a heredoc.
            if arith > 0 or brace > 0:
                i = j
                at_word_start = False
                continue
            dashed = False
            if j < n and line[j] == "-":
                dashed = True
                out.append("-")
                j += 1
            while j < n and line[j] in " \t":
                out.append(line[j])
                j += 1
            delim, j = _read_heredoc_delim(line, j, out)
            if delim:
                delims.append((delim, dashed, bool(SIMPLE_DELIM.match(delim))))
            i = j
            at_word_start = False
            continue

        out.append(c)
        # A `#` starts a comment only when it begins a word.
        at_word_start = c in " \t;|&(){}<>"
        i += 1

    return "".join(out), delims, quote, arith, brace


def preprocess(cmd: str):
    """Strip `#` comments and here-document bodies before segment analysis.

    Returns `(text, force_block)`. Runs a single quote-, arithmetic-, and
    `${}`-aware scan (state carried across lines) so that neither a comment nor a
    construct inside a quoted string / arithmetic / parameter expansion can be
    mistaken for something that hides a real `codex` command.

    Comment text and here-doc bodies with a trusted delimiter are dropped. For an
    untrusted delimiter (one we may have mis-parsed) the dropped body is scanned
    line by line first; if any line invokes `codex`, `force_block` is set so the
    caller blocks anyway. If a here-doc's closing delimiter never appears
    (malformed), its buffered lines are kept so a real command can never hide
    behind an unterminated here-doc.
    """
    lines = cmd.split("\n")
    out = []
    force_block = False
    i, n = 0, len(lines)
    quote = None
    arith = 0
    brace = 0
    while i < n:
        stripped, delims, quote, arith, brace = _scan_line(
            lines[i], quote, arith, brace
        )
        out.append(stripped)
        i += 1
        for delim, dashed, trusted in delims:
            body = []
            terminated = False
            while i < n:
                bl = lines[i]
                i += 1
                candidate = bl.lstrip("\t") if dashed else bl
                if candidate == delim:
                    terminated = True
                    break
                body.append(bl)
            if not terminated:
                out.extend(body)
            elif not trusted and any(
                _segment_invokes_codex(seg)
                for bl in body
                for seg in split_segments(bl)
            ):
                force_block = True
    return "\n".join(out), force_block


def split_segments(cmd: str):
    """Split `cmd` into command segments, honoring quotes.

    Splits on the shell control operators `;` `|` `&` and newlines, and starts a
    fresh segment for command substitutions `$(...)` and backticks (their body
    is itself a command). Single- and double-quoted text does NOT split, but a
    `$(...)` / backtick substitution *inside* double quotes still does. Quote
    characters are kept in the segment text so that `shlex.split` later performs
    the real tokenization (e.g. `FOO="a b" codex` stays one env-assignment token
    plus `codex`, rather than being mis-split into `FOO=a` and `b`).
    """
    segments = []
    buf = []
    stack = []  # nested contexts: "'", '"', "$(", "`"

    def flush():
        s = "".join(buf).strip()
        if s:
            segments.append(s)
        buf.clear()

    i, n = 0, len(cmd)
    while i < n:
        c = cmd[i]
        top = stack[-1] if stack else None

        if top == "'":  # single quotes: everything literal until the close
            buf.append(c)
            if c == "'":
                stack.pop()
            i += 1
            continue

        if c == "\\":  # backslash escape: keep both chars, drop control meaning
            buf.append(c)
            if i + 1 < n:
                buf.append(cmd[i + 1])
                i += 2
            else:
                i += 1
            continue

        if c == "'" and top != '"':
            stack.append("'")
            buf.append(c)
            i += 1
            continue

        if c == '"':
            if top == '"':
                stack.pop()
            else:
                stack.append('"')
            buf.append(c)
            i += 1
            continue

        if c == "$" and i + 1 < n and cmd[i + 1] == "(":  # command substitution
            flush()  # the inner command is its own segment; drop the `$(`
            stack.append("$(")
            i += 2
            continue

        if c == "$" and i + 1 < n and cmd[i + 1] == "{":  # ${var}: not a command
            buf.append("${")
            i += 2
            continue

        if c == "`":  # backtick command substitution (toggle)
            flush()
            if top == "`":
                stack.pop()
            else:
                stack.append("`")
            i += 1
            continue

        if c == ")" and top == "$(":
            flush()
            stack.pop()
            i += 1
            continue

        if top == '"':  # inside double quotes: literal text (subs handled above)
            buf.append(c)
            i += 1
            continue

        # Unquoted context (top is None or "$(").
        if c in ";|&\n":
            flush()
            i += 1
            continue
        if c == ")":  # stray close paren -> segment boundary (regex parity)
            flush()
            i += 1
            continue

        buf.append(c)
        i += 1

    flush()
    return segments


def _segment_invokes_codex(seg: str) -> bool:
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
    return i < len(tokens) and os.path.basename(tokens[i]) == "codex"


def invokes_codex(cmd: str) -> bool:
    # No `"codex" not in cmd` fast-path here: obfuscated forms such as
    # `co"dex" exec` or `co\d\ex exec` do not contain the literal substring yet
    # still run `codex` once the shell resolves quotes / escapes. Always run the
    # full quote-, comment-, and heredoc-aware analysis.
    cmd = join_continuations(cmd)
    cmd, force_block = preprocess(cmd)
    if force_block:
        return True
    for seg in split_segments(cmd):
        if _segment_invokes_codex(seg):
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
