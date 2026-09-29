#!/usr/bin/env python3
"""Regression tests for the check-jargon Stop hook.

Run with:  python3 tests/test_check_jargon.py

Covers two things the hook must get right:
  - `[block]` in the note column marks a term that stops the turn (exit 2);
    every other matching term is recorded only (exit 0).
  - the end-to-end stdin -> exit-code path, driven through a fake transcript.
"""
import importlib.util
import json
import os
import pathlib
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
HOOK_PATH = os.path.join(
    HERE, "..", "private_dot_claude", "hooks", "executable_check-jargon.py"
)
GLOSSARY = pathlib.Path(HERE).parent / "private_dot_claude" / "docs" / "glossary" / "jargon.md"

spec = importlib.util.spec_from_file_location("check_jargon", HOOK_PATH)
hook = importlib.util.module_from_spec(spec)
spec.loader.exec_module(hook)

PATTERNS = hook.load_patterns(GLOSSARY)

# Terms that must stop the turn. Confirmed clean over 541 hits (09-11 .. 09-19).
EXPECT_BLOCKING = {"司令塔", "HQ", "枠", "班", "レーン", "受け皿", "検算"}

# Each case: (label, assistant text, expected exit code)
CASES = [
    ("blocking: 司令塔", "司令塔が dev と移行元の URL を対で出します。", 2),
    ("blocking: 検算", "マージ前に検算を回して数を合わせました。", 2),
    ("blocking: N 枠", "並列セッションを 5 枠で走らせます。", 2),
    ("recorded only: 書庫", "成果物は書庫にまとめて置いてあります。", 0),
    ("recorded only: 写し", "移行元の写しを 9/15 版まで進めました。", 0),
    ("clean text", "移行元のミラーを 9/15 版まで更新し、テストをスキップに切り替えました。", 0),
    ("inside code span", "`司令塔` という語は使いません。", 0),
    ("rate-limit 枠 is legitimate", "週間の利用枠が 80% に達しました。", 0),
]


def make_home(tmpdir):
    """Build a throwaway HOME holding this repo's glossary.

    The hook resolves the glossary and its state file under `Path.home()`, so the
    test must not run against the real one: a passing run would otherwise append
    to ~/.claude/state/jargon-hits.jsonl and skew the measurements.
    """
    home = pathlib.Path(tmpdir) / "home"
    glossary_dir = home / ".claude" / "docs" / "glossary"
    glossary_dir.mkdir(parents=True, exist_ok=True)
    (glossary_dir / "jargon.md").write_text(
        GLOSSARY.read_text(encoding="utf-8"), encoding="utf-8"
    )
    return home


def run_hook(text, tmpdir, home):
    """Drive the hook end to end through a fake transcript and stdin payload."""
    transcript = pathlib.Path(tmpdir) / "transcript.jsonl"
    rec = {"type": "assistant", "message": {"content": [{"type": "text", "text": text}]}}
    transcript.write_text(json.dumps(rec, ensure_ascii=False) + "\n", encoding="utf-8")
    payload = {"session_id": "test", "transcript_path": str(transcript), "cwd": tmpdir}
    env = dict(os.environ, HOME=str(home))
    proc = subprocess.run(
        [sys.executable, HOOK_PATH],
        input=json.dumps(payload),
        capture_output=True,
        text=True,
        env=env,
    )
    return proc.returncode, proc.stderr


def main() -> int:
    failures = []

    blocking = {term for term, _pat, _std, is_block in PATTERNS if is_block}
    if blocking != EXPECT_BLOCKING:
        failures.append(
            ("[block] set", f"got={sorted(blocking)} want={sorted(EXPECT_BLOCKING)}")
        )
        print(f"[FAIL] [block] set  got={sorted(blocking)}")
    else:
        print(f"[ok ] [block] set  {sorted(blocking)}")

    with tempfile.TemporaryDirectory() as tmpdir:
        home = make_home(tmpdir)
        for label, text, expected in CASES:
            code, stderr = run_hook(text, tmpdir, home)
            status = "ok " if code == expected else "FAIL"
            print(f"[{status}] {label:30s} exit={code} want={expected}")
            if code != expected:
                failures.append((label, f"exit={code} want={expected} stderr={stderr!r}"))
            elif code == 2 and "標準語" not in stderr:
                failures.append((label, f"blocked without a rewrite instruction: {stderr!r}"))
                print(f"[FAIL] {label}: stderr lacks the rewrite instruction")

    print()
    total = len(CASES) + 1
    print(f"{total - len(failures)}/{total} passed")
    if failures:
        print("\nFAILURES:")
        for label, detail in failures:
            print(f"  - {label}: {detail}")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
