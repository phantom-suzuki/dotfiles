#!/usr/bin/env python3
"""Regression tests for the check-question PreToolUse hook.

Run with:  python3 tests/test_check_question.py

Loads the hook by file path (its filename is hyphenated and carries chezmoi's
`executable_` attribute prefix) and exercises `check()` against a table of
question texts taken from real sessions.
"""
import importlib.util
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
HOOK_PATH = os.path.join(
    HERE, "..", "private_dot_claude", "hooks", "executable_check-question.py"
)
GLOSSARY = os.path.join(
    HERE, "..", "private_dot_claude", "docs", "glossary", "jargon.md"
)

spec = importlib.util.spec_from_file_location("check_question", HOOK_PATH)
hook = importlib.util.module_from_spec(spec)
spec.loader.exec_module(hook)

import pathlib

JARGON = hook.load_jargon(pathlib.Path(GLOSSARY))

# Each case: (label, question, should_deny)
CASES = [
    # --- MUST DENY: real questions from sessions (2026-09-05 .. 09-19) --------
    ("bare number as subject", "#7001 の進め方をどうしますか？", True),
    ("bare number mid-sentence",
     "#6863 の承認者を設定するには、誰を置くか決める必要があります", True),
    ("two bare numbers",
     "#7001 と #6863 は同じ backend-deploy.yml を触ります。どう進めますか", True),
    ("demonstrative start", "このドラフトで進めてよいですか", True),
    ("too short", "回答の期限を入れますか", True),
    ("too short 2", "Slack への送信はどうしますか", True),
    ("arrow symbol",
     "「追加機能」Milestone は、どの位置に置きますか？"
     "（現在は「安定稼働・段階移行」→「リファクタリング」の順です）", True),
    ("jargon: 司令塔",
     "目視確認はどう進めますか。司令塔が dev と移行元の URL を対で出す形にしますか", True),
    ("jargon: レーン",
     "並列レーンを 3 本に増やして、同時に別の Issue を進めてよいですか", True),
    ("jargon: 検算",
     "マージ前に検算を回して、数が合ってから進めてよいですか", True),
    ("jargon: 受け皿",
     "成婚ストーリーの一覧ページの受け皿は、専用テンプレートの新設でよいですか", True),
    ("jargon: 写し",
     "移行元の写しを 9/15 版まで進める時機は、第 2 回の差分取り込みに乗せますか", True),
    ("jargon: 飛ばし",
     "ミラーを読むテスト 3 本は、GitHub Actions 上で飛ばしに裏返してよいですか", True),
    ("circled-number prefix then bare number",
     "⑲-2 #2746 の実装に、いま着手しますか", True),
    ("demonstrative with brackets", "上記の 2 案のうち、どちらで進めますか", True),

    # --- MUST ALLOW: well-formed questions -----------------------------------
    ("named subject with number",
     "Percona Toolkit を導入する Issue（#7001）は、"
     "同じデプロイ定義を触る承認者設定の Issue（#6863）とどちらを先に進めますか", False),
    ("named subject, no number",
     "広島県のデートスポット一覧の紹介文が山口県の文章のままです。"
     "/spot/hiroshima/ にはどう出しますか", False),
    ("markdown link form",
     "用語集を整備する [#122](https://example.com/issues/122) を、"
     "このブランチで閉じてよいですか", False),
    ("standard katakana terms",
     "移行元のミラーを読むテスト 3 本は、GitHub Actions 上でスキップ扱いにしてよいですか", False),
    ("rate-limit 枠 is legitimate Japanese",
     "週間の利用枠が 80% を超えました。アカウントを切り替えて作業を続けますか", False),
    ("long enough, names the target",
     "現行 Parms（PHP）の改修 Epic と配下 Feature の component はどうしますか", False),
    ("code span with hash is not a bare number",
     "コミットメッセージの `refs #123` という書き方を、"
     "この리포지토리の規約として採用しますか".replace("리포지토리", "リポジトリ"), False),
    ("URL containing digits after hash",
     "手順書（https://example.com/docs#section-42）の書き方に、"
     "今回の変更を合わせてよいですか", False),
]


def main() -> int:
    if not JARGON:
        print("FAIL: jargon.md からパターンを 1 つも読めていない")
        return 1
    print(f"loaded {len(JARGON)} jargon patterns\n")

    failures = []
    for label, question, expected in CASES:
        problems = hook.check(question, JARGON)
        got = bool(problems)
        status = "ok " if got == expected else "FAIL"
        verdict = "DENY " if got else "allow"
        want = "DENY " if expected else "allow"
        print(f"[{status}] {label:38s} got={verdict} want={want}")
        if got != expected:
            failures.append((label, question, expected, problems))

    print()
    total = len(CASES)
    print(f"{total - len(failures)}/{total} passed")
    if failures:
        print("\nFAILURES:")
        for label, question, expected, problems in failures:
            print(f"  - {label}: want_deny={expected}")
            print(f"      question={question!r}")
            print(f"      problems={problems}")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
