"""The comparison page written by `graphghan options`: every variant at every gauge, with stats."""
from __future__ import annotations

import json


def build_options_html(title, entries):
    """entries: list of dicts {variant, gauge, width, height, size_in, colors, changes_mean, changes_max, hours, rows, palette}."""
    cards = []
    for e in entries:
        cards.append(
            f'<article><h2>{e["variant"]} · {e["gauge"]}</h2>'
            f'<canvas data-key="{e["variant"]}_{e["gauge"]}"></canvas>'
            f'<table><tr><th>Stitches × rows</th><td>{e["width"]} × {e["height"]}</td></tr>'
            f'<tr><th>Finished</th><td>{e["size_in"][0]}″ × {e["size_in"][1]}″</td></tr>'
            f'<tr><th>Colors</th><td>{len(e["colors"])}</td></tr>'
            f'<tr><th>Changes / row</th><td>mean {e["changes_mean"]}, max {e["changes_max"]}</td></tr>'
            f'<tr><th>Stitching</th><td>~{e["hours"]} h</td></tr></table></article>')
    data = json.dumps({f'{e["variant"]}_{e["gauge"]}': e for e in entries})
    return f"""<meta charset="utf-8"><title>{title} options</title>
<style>body{{font-family:system-ui;margin:24px;background:#f4f5f0;color:#1f2a24}}article{{margin:0 0 32px;background:#fff;padding:16px;border:1px solid #d3d9d0;border-radius:6px}}
canvas{{display:block;max-width:100%;margin:8px 0}}table{{border-collapse:collapse}}th{{text-align:left;padding:4px 12px 4px 0;color:#5b675f;font-weight:600}}td{{padding:4px 0}}</style>
<h1>{title}: options</h1>
{''.join(cards)}
<script>
const DATA={data};
for (const [key,e] of Object.entries(DATA)) {{
  const cv=document.querySelector(`canvas[data-key="${{key}}"]`), ctx=cv.getContext('2d');
  const hex=Object.fromEntries(e.palette.map(p=>[p.code,p.hex]));
  const cw=Math.max(2,Math.floor(1100/e.width)), ch=Math.max(2,Math.round(cw*e.cell_aspect));
  cv.width=e.width*cw; cv.height=e.height*ch;
  e.rows.forEach((s,y)=>{{let x=0; for (const m of s.matchAll(/(\\d+)([A-Za-z])/g)) {{ctx.fillStyle=hex[m[2]]; ctx.fillRect(x*cw,y*ch,+m[1]*cw,ch); x+=+m[1];}}}});
}}
</script>"""
