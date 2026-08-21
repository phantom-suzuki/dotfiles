#!/usr/bin/env python3
"""Before/After スクリーンショットの横並び比較ページを生成する。

usage:
  build_compare.py --shots <dir> --out <file.html> [--title T] [--base main] [--head feature/x]
                   [--note "<screen>=<説明>"]... [--embed]

ペアの組み方: ファイル名 "NN-<screen>-before.png" と "MM-<screen>-after.png" を <screen> で対応付ける。
after だけのもの、および "NN-<screen>-after-<variant>.png"（派生状態）は単独画像として並べる。--embed で画像を data URI として埋め込む（Artifact 公開用）。
"""
import argparse, base64, html, pathlib, re, sys

NAME_RE = re.compile(r"^(\d+)-(.+?)-(before|after)(?:-(.+))?\.png$")

def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--shots", required=True); ap.add_argument("--out", required=True)
    ap.add_argument("--title", default="UI Before/After 比較")
    ap.add_argument("--base", default="main"); ap.add_argument("--head", default="head")
    ap.add_argument("--note", action="append", default=[], help="<screen>=<説明>")
    ap.add_argument("--embed", action="store_true")
    a = ap.parse_args()
    shots = pathlib.Path(a.shots); out = pathlib.Path(a.out)
    notes = dict(n.split("=", 1) for n in a.note if "=" in n)

    screens: dict[str, dict[str, pathlib.Path]] = {}
    order: list[str] = []
    for p in sorted(shots.glob("*.png")):
        m = NAME_RE.match(p.name)
        if not m:
            print(f"skip (name pattern): {p.name}", file=sys.stderr); continue
        _, screen, kind, variant = m.groups()
        # "-after-<variant>" は派生状態（閲覧者名あり・モバイル幅 等）。ペアにせず単独画像として扱う
        if variant:
            screen = f"{screen} ({variant})"
        if screen not in screens:
            screens[screen] = {}; order.append(screen)
        screens[screen][kind] = p

    def src(p: pathlib.Path) -> str:
        if a.embed:
            return "data:image/png;base64," + base64.b64encode(p.read_bytes()).decode()
        return p.name

    def card(label, cls, p, alt):
        return (f'<div class="card"><div class="label {cls}">{html.escape(label)}</div>'
                f'<img src="{src(p)}" alt="{html.escape(alt)}" onclick="openLightbox(this)"></div>')

    body, pairs, singles = [], 0, 0
    for i, screen in enumerate(order, 1):
        s = screens[screen]; label = screen.replace("-", " ")
        note = notes.get(screen)
        if "before" in s and "after" in s:
            pairs += 1
            body.append(f'<h3 class="pair-title">{i}. {html.escape(label)}</h3><div class="pair">'
                        f'{card("Before（" + a.base + "）", "label-before", s["before"], label + " before")}'
                        f'{card("After（" + a.head + "）", "label-after", s["after"], label + " after")}</div>')
        else:
            singles += 1
            p = s.get("after") or s.get("before")
            kind = "After（" + a.head + "）" if "after" in s else "Before（" + a.base + "）"
            body.append(f'<h3 class="pair-title">{i}. {html.escape(label)}</h3><div class="pair single">'
                        f'{card(kind, "label-single", p, label)}</div>')
        if note:
            body.append(f'<div class="note"><strong>変更点:</strong> {html.escape(note)}</div>')

    page = f"""<!DOCTYPE html>
<html lang="ja"><head><meta charset="UTF-8"><title>{html.escape(a.title)}</title>
<style>
* {{ margin: 0; padding: 0; box-sizing: border-box; }}
body {{ font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; background: #f5f5f5; color: #333; padding: 24px; }}
h1 {{ text-align: center; margin-bottom: 8px; font-size: 1.6rem; }}
.subtitle {{ text-align: center; color: #666; margin-bottom: 32px; font-size: 0.9rem; }}
.pair-title {{ margin: 24px 0 8px; font-size: 0.95rem; }}
.pair {{ display: flex; gap: 16px; margin-bottom: 8px; align-items: flex-start; }}
.pair .card {{ flex: 1; background: #fff; border-radius: 8px; box-shadow: 0 1px 4px rgba(0,0,0,0.1); overflow: hidden; }}
.pair .card img {{ width: 100%; display: block; cursor: zoom-in; }}
.pair .card .label {{ padding: 8px 12px; font-weight: 600; font-size: 0.85rem; text-align: center; }}
.label-before {{ background: #dbeafe; color: #1e40af; }}
.label-after {{ background: #fef3c7; color: #92400e; }}
.label-single {{ background: #fce7f3; color: #9d174d; }}
.note {{ background: #fff7ed; border-left: 4px solid #f59e0b; padding: 12px 16px; border-radius: 4px; margin-bottom: 16px; font-size: 0.85rem; }}
.note strong {{ color: #b45309; }}
.single {{ max-width: 50%; }}
@media (max-width: 900px) {{ .pair {{ flex-direction: column; }} .single {{ max-width: 100%; }} }}
.lightbox {{ display: none; position: fixed; inset: 0; background: rgba(0,0,0,0.85); z-index: 1000; justify-content: center; align-items: flex-start; overflow: auto; cursor: zoom-out; padding: 24px; }}
.lightbox.active {{ display: flex; }}
.lightbox img {{ max-width: 95vw; border-radius: 4px; }}
</style></head><body>
<h1>{html.escape(a.title)}</h1>
<p class="subtitle">{html.escape(a.base)}（左）vs {html.escape(a.head)}（右）</p>
{"".join(body)}
<div class="lightbox" id="lightbox" onclick="closeLightbox()"><img id="lightbox-img" src="" alt=""></div>
<script>
function openLightbox(el) {{ document.getElementById('lightbox-img').src = el.src; document.getElementById('lightbox').classList.add('active'); }}
function closeLightbox() {{ document.getElementById('lightbox').classList.remove('active'); }}
document.addEventListener('keydown', e => {{ if (e.key === 'Escape') closeLightbox(); }});
</script></body></html>"""
    out.write_text(page)
    print(f"wrote {out} ({out.stat().st_size} bytes): {pairs} pairs, {singles} singles")
    return 0

if __name__ == "__main__":
    sys.exit(main())
