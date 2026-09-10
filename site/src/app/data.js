const HEX_RE = /^#[0-9a-fA-F]{6}$/;

export function decodeChart(doc) {
  const codes = doc.palette.map(p => p.code);
  const hex = doc.palette.map(p => HEX_RE.test(p.hex) ? p.hex : '#888888');
  const light = hex.map(h => { const v = parseInt(h.slice(1), 16); const r = v >> 16, g = (v >> 8) & 255, b = v & 255; return (r * 299 + g * 587 + b * 114) / 1000 < 140; });
  const idx = Object.fromEntries(codes.map((c, i) => [c, i]));
  const W = doc.width, H = doc.height;
  const grid = new Uint8Array(W * H);
  const re = /(\d+)([A-Za-z])/g;
  const runsTop = doc.rows.map((s, y) => { const out = []; let x = 0, m; re.lastIndex = 0; while ((m = re.exec(s))) { const ci = idx[m[2]], n = +m[1]; out.push([ci, n]); grid.fill(ci, y * W + x, y * W + x + n); x += n; } return out; });
  return { doc, W, H, codes, hex, light, grid, runsTop };
}

export const rowSide = row => (row % 2 === 1 ? 'RS' : 'WS');
export const yOfRow = (chart, row) => chart.H - row;

export function workingRuns(chart, row) {
  const runs = chart.runsTop[yOfRow(chart, row)].slice();
  return row % 2 === 1 ? runs.reverse() : runs;
}

export function rowStats(chart, row) {
  const runs = workingRuns(chart, row);
  return { sts: runs.reduce((s, r) => s + r[1], 0), changes: runs.length - 1, colors: new Set(runs.map(r => r[0])).size };
}

export function writtenLines(chart) {
  const out = [];
  for (let r = 1; r <= chart.H; r++) {
    const runs = workingRuns(chart, r);
    out.push(`Row ${String(r).padStart(3, ' ')} (${rowSide(r)}): ` + runs.map(([c, n]) => `${n} ${chart.codes[c]}`).join(', ') + `  (${runs.reduce((s, x) => s + x[1], 0)} sts)`);
  }
  return out;
}
