#!/usr/bin/env python3
"""PoC フィードバック表の J・L・M・N 列（ステータス・対応内容・完了日・備考）を書く。

  write-cells.py spec.json            書き込む
  write-cells.py --json '<配列>'      ファイルを作らず、引数の JSON で書き込む（無人実行はこちら）
  write-cells.py ... --dry-run        送る要求を標準出力に出すだけ

spec.json は行ごとの配列。row は表の行番号（1 始まり。データは 8 行目から）。
書かない列はキーごと省く。B〜I 列（報告者の欄）と K 列（担当者）は書かない。

  [{"row": 8, "status": "対応中", "progress": "・改修を起票\n・Issue: #496",
    "done": "2026/10/09", "note": "・関連: #463"}]

progress と note の `#123` は、この repo の Issue へのリンクにする（リッチテキスト）。
"""
import json
import re
import shutil
import subprocess
import sys

SHEET_ID = "1vi7fxI8_P5yi_t9jUAR_LbQ2jfMfnhBpUWFSl5C5iFM"
TAB_GID = 0  # 不具合管理表
ISSUE_URL = "https://github.com/mationinc/business-card-registry/issues/"
STATUSES = {"新規", "調査中", "対応中", "検証中", "完了", "保留"}
COLUMNS = {"status": 9, "progress": 11, "done": 12, "note": 13}  # 0 始まり（J / L / M / N）


def u16(text: str) -> int:
    return len(text.encode("utf-16-le")) // 2


def rich(text: str) -> dict:
    runs = [{"startIndex": 0, "format": {}}]
    for m in re.finditer(r"#(\d+)", text):
        runs.append({"startIndex": u16(text[: m.start()]), "format": {"link": {"uri": ISSUE_URL + m.group(1)}}})
        runs.append({"startIndex": u16(text[: m.end()]), "format": {}})
    end = u16(text)
    kept = []
    for r in runs:
        if r["startIndex"] >= end:
            continue
        if kept and kept[-1]["startIndex"] == r["startIndex"]:
            kept[-1] = r
        else:
            kept.append(r)
    return {
        "userEnteredValue": {"stringValue": text},
        "textFormatRuns": kept,
        "userEnteredFormat": {"wrapStrategy": "WRAP", "verticalAlignment": "TOP"},
    }


def plain(text: str) -> dict:
    return {"userEnteredValue": {"stringValue": text}}


def requests(spec: list) -> list:
    out = []
    for item in spec:
        row = int(item["row"])
        if row < 8:
            raise SystemExit(f"row {row}: データは 8 行目から")
        if "status" in item and item["status"] not in STATUSES:
            raise SystemExit(f"row {row}: ステータス {item['status']!r} はプルダウンに無い")
        for key, col in COLUMNS.items():
            if key not in item:
                continue
            value = item[key]
            cell = rich(value) if key in ("progress", "note") and value else plain(value)
            fields = "userEnteredValue"
            if "textFormatRuns" in cell:
                fields += ",textFormatRuns,userEnteredFormat.wrapStrategy,userEnteredFormat.verticalAlignment"
            out.append({"updateCells": {
                "start": {"sheetId": TAB_GID, "rowIndex": row - 1, "columnIndex": col},
                "rows": [{"values": [cell]}],
                "fields": fields,
            }})
    return out


def main() -> None:
    args = [a for a in sys.argv[1:] if a != "--dry-run"]
    if not args:
        raise SystemExit(__doc__)
    if args[0] == "--json":
        if len(args) < 2:
            raise SystemExit("--json の後に JSON の配列を渡す")
        spec = json.loads(args[1])
    else:
        with open(args[0], encoding="utf-8") as f:
            spec = json.load(f)
    body = {"requests": requests(spec)}
    if "--dry-run" in sys.argv:
        print(json.dumps(body, ensure_ascii=False, indent=2))
        return
    gws = shutil.which("gws")
    if not gws:
        raise SystemExit("gws が PATH に無い")
    res = subprocess.run(
        [gws, "sheets", "spreadsheets", "batchUpdate",
         "--params", json.dumps({"spreadsheetId": SHEET_ID}),
         "--json", json.dumps(body, ensure_ascii=False)],
        capture_output=True, text=True,
    )
    data = json.loads(res.stdout or "{}")
    if res.returncode != 0 or "error" in data:
        raise SystemExit(f"書き込みに失敗: {data.get('error', res.stderr)}")
    print(f"updated {len(data.get('replies', []))} cells")


if __name__ == "__main__":
    main()
