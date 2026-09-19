#!/usr/bin/env python3
"""PreToolUse hook: AskUserQuestion の質問文を点検し、伝わらない形なら差し戻す。

質問ダイアログは本文と切り離して表示される。そのため質問文が単独で意味を持たないと、
ユーザーは何を聞かれているのか分からないまま選択を迫られる。実測（2026-09-19、直近 7 日）では
質問 1,219 件のうち 258 件（21%）が説明のない `#番号` を含み、66 件が `#番号` から始まっていた。

差し戻す条件は次の 5 つ。いずれも質問文（question）が対象で、選択肢は対象外にする。
選択肢は短い語句で書く規律（communication-style.md）があり、そこまで縛ると書けなくなるため。

  1. 番号だけの主語         : `#123` に説明が無い
  2. 冒頭が番号か指示語     : 「#7001 の進め方は」「このドラフトで」
  3. 記号で語をつなぐ       : `→` `⇒` `←`
  4. 内輪語                 : docs/glossary/jargon.md の検出パターン
  5. 短すぎる               : 全角 20 文字未満は対象が特定できていない

差し戻しの理由はモデルへ返り、書き直して再度呼び出せる。ユーザーの操作は要らない。
点検した内容は ~/.claude/state/question-lint.jsonl に記録する。
"""
import sys
import os
import re
import json
import datetime
import pathlib

# jargon.md の表から「| 内輪語 | `パターン` | 標準語 | 補足 |」を取り出す
ROW = re.compile(r"^\|([^|]+)\|([^|]+)\|([^|]+)\|([^|]*)\|\s*$")
BACKTICKED = re.compile(r"^`([^`]+)`$")

# [#123](URL) の形になっていない裸の番号。直後に括弧書きの説明があるものは許す。
BARE_NUMBER = re.compile(r"(?<![\[\w/#])#(\d{2,6})\b(?!\s*[）)])")
LINKED_NUMBER = re.compile(r"\[#\d{2,6}\]\(")
# 冒頭の主語が番号・指示語・丸数字だけの形。丸数字は先頭の通し番号として実際に使われている。
HEAD_BAD = re.compile(
    r"^[\s　]*(?:[（(]?[①-⑳㉑-㉟⑴-⒇][\-‐–—ー]?\d*[）)]?[\s　]*)?"
    r"(?:#\d|この|その|あの|上記|下記|これ|それ)"
)
ARROW = re.compile(r"[→⇒←↔]")
INLINE_CODE = re.compile(r"`[^`\n]*`")
URL = re.compile(r"https?://\S+")

MIN_LEN = 20  # 文字数の下限。これを下回る質問は対象が書かれていない


def load_jargon(glossary):
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


def strip_noise(text):
    """コードとリンク先 URL を落とす。この中の語は点検の対象にしない。"""
    text = INLINE_CODE.sub(" ", text)
    text = URL.sub(" ", text)
    return text


def check(question, jargon):
    """質問文 1 件を点検し、問題があれば理由の一覧を返す。"""
    problems = []
    body = strip_noise(question)
    stripped = question.strip()

    if len(stripped) < MIN_LEN:
        problems.append(
            f"質問文が {len(stripped)} 文字しかない。"
            "対象の名前・誰が・何を決めるかを入れて書き直す"
        )

    if HEAD_BAD.match(stripped):
        problems.append(
            "質問文が番号か指示語で始まっている。対象の名前を主語にする"
            "（例:「#7001 の進め方は」→「Percona Toolkit を導入する Issue（#7001）の進め方は」）"
        )

    bare = [m.group(0) for m in BARE_NUMBER.finditer(body)]
    if bare and not LINKED_NUMBER.search(body):
        problems.append(
            f"説明の無い番号がある: {' / '.join(dict.fromkeys(bare))}。"
            "「何を指すか（#123）」の形で名前を添える"
        )

    if ARROW.search(body):
        problems.append(
            "記号（→ など）で語をつないでいる。質問文は文にして書く"
        )

    hits = [(term, standard) for term, pat, standard in jargon if pat.search(body)]
    if hits:
        detail = " / ".join(
            "「" + term + "」は「" + standard + "」と書く"
            for term, standard in dict.fromkeys(hits)
        )
        problems.append("内輪語が混ざっている: " + detail)

    return problems


def record(data, findings, total):
    """点検の結果を記録する。失敗しても点検の結果には影響させない。

    問題が無かった回も記録する。差し戻しの割合を測れるようにするためと、
    このフックが実際に呼ばれているかを確かめられるようにするため。
    """
    try:
        state_dir = pathlib.Path.home() / ".claude" / "state"
        state_dir.mkdir(parents=True, exist_ok=True)
        rec = {
            "at": datetime.datetime.now().astimezone().isoformat(timespec="seconds"),
            "session_id": str(data.get("session_id") or ""),
            "cwd": data.get("cwd", os.getcwd()),
            "questions": total,
            "findings": findings,
        }
        with (state_dir / "question-lint.jsonl").open("a", encoding="utf-8") as f:
            f.write(json.dumps(rec, ensure_ascii=False) + "\n")
    except Exception:
        pass


def main():
    try:
        data = json.load(sys.stdin)
    except Exception:
        sys.exit(0)  # 読めない入力では止めない

    if data.get("tool_name") != "AskUserQuestion":
        sys.exit(0)

    questions = (data.get("tool_input") or {}).get("questions") or []
    if not isinstance(questions, list) or not questions:
        sys.exit(0)

    glossary = pathlib.Path.home() / ".claude" / "docs" / "glossary" / "jargon.md"
    jargon = load_jargon(glossary)

    findings = []
    for i, q in enumerate(questions, 1):
        if not isinstance(q, dict):
            continue
        text = q.get("question", "") or ""
        problems = check(text, jargon)
        if problems:
            findings.append({"index": i, "question": text, "problems": problems})

    record(data, findings, len(questions))

    if not findings:
        sys.exit(0)

    lines = [
        "質問文が単独で読めません。質問ダイアログは本文と切り離して表示されるため、"
        "質問文だけで「何について・誰が・何を決めるか」が分かる必要があります。"
        "下の指摘を直して AskUserQuestion を呼び直してください（ユーザーの操作は要りません）。",
        "",
    ]
    for f in findings:
        lines.append(f"質問 {f['index']}: {f['question']}")
        for p in f["problems"]:
            lines.append(f"  - {p}")
    lines += [
        "",
        "型: 対象の名前（番号は括弧に入れる）＋ 誰が ＋ 何を決めるか ＋ なぜ今か。"
        "決まりは ~/.claude/rules/question-blocking.md、"
        "用語は ~/.claude/docs/glossary/jargon.md を読んでください。",
    ]

    out = {
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": "\n".join(lines),
        }
    }
    print(json.dumps(out, ensure_ascii=False))
    sys.exit(0)


if __name__ == "__main__":
    main()
