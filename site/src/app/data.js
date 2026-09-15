const HEX_RE = /^#[0-9a-fA-F]{6}$/;
const RUN_RE = /(\d+)([A-Za-z]{1,3})/g;

export function parseRuns(s) {
  const out = []; let m; RUN_RE.lastIndex = 0;
  while ((m = RUN_RE.exec(s))) out.push([m[2], +m[1]]);
  return out;
}

const CELL_KIND_NOUNS = { stitch: 'stitches', block: 'blocks', tile: 'tiles', motif: 'motifs', pair: 'pairs' };

// Mirrors graphghan.chartdoc.cell_kind (docs/chart-format.md §Cells), scoped to the chart object
// rather than the whole document. Absent, or a kind outside the enum, means `stitch`.
export function cellKind(chart) {
  const kind = chart && chart.cell && chart.cell.kind;
  return Object.hasOwn(CELL_KIND_NOUNS, kind) ? kind : 'stitch';
}

export function cellNoun(chart) {
  return CELL_KIND_NOUNS[cellKind(chart)];
}

const UNIT_FOR_KIND = { stitch: 'stitches', tile: 'tiles' };

// Mirrors graphghan.chartdoc.size_derives: a finished size only derives when gauge.unit and
// chart.cell.kind name the same thing. A missing/null unit reads as 'stitches'; a kind with no
// table entry (block, motif, pair) never matches anything.
export function sizeDerives(doc) {
  const unit = (doc.gauge && doc.gauge.unit) || 'stitches';
  return UNIT_FOR_KIND[cellKind(doc.chart)] === unit;
}

// Mirrors graphghan.chartdoc.sequence (docs/chart-format.md §technique). Explicit passes win;
// `rows` and `rounds` are derived; anything else returns null (display-only).
export function sequence(doc) {
  if (Array.isArray(doc.passes)) {
    return doc.passes.map(p => ({ label: p.label || '', side: p.side ?? null, direction: p.direction ?? null, gridRow: p.grid_row ?? null,
      runs: p.runs.map(r => ({ code: r.code, count: r.count, x0: r.x0 ?? null })) }));
  }
  const t = doc.technique || {};
  if (t.type !== 'rows' && t.type !== 'rounds') return null;
  const H = doc.rows.length, start = t.start || 'bottom', firstSide = t.first_side || 'RS', rsDir = t.rs_direction || 'rtl';
  const other = s => (s === 'RS' ? 'WS' : 'RS'), flip = d => (d === 'rtl' ? 'ltr' : 'rtl');
  const passes = [];
  for (let k = 1; k <= H; k++) {
    const y = start === 'bottom' ? H - k : k - 1;
    let side, direction;
    if (t.type === 'rows') { side = k % 2 === 1 ? firstSide : other(firstSide); direction = side === 'RS' ? rsDir : flip(rsDir); }
    else { side = firstSide; direction = rsDir; }
    const runs = []; let x = 0;
    for (const [code, n] of parseRuns(doc.rows[y])) { runs.push({ code, count: n, x0: x }); x += n; }
    if (direction === 'rtl') runs.reverse();
    passes.push({ label: `${t.type === 'rows' ? 'Row' : 'Round'} ${k}`, side, direction, gridRow: y, runs });
  }
  return passes;
}

export function decodeChart(doc) {
  const codes = doc.palette.map(p => p.code);
  const hex = doc.palette.map(p => HEX_RE.test(p.hex) ? p.hex : '#888888');
  const light = hex.map(h => { const v = parseInt(h.slice(1), 16); const r = v >> 16, g = (v >> 8) & 255, b = v & 255; return (r * 299 + g * 587 + b * 114) / 1000 < 140; });
  const idx = Object.fromEntries(codes.map((c, i) => [c, i]));
  const W = doc.chart.width, H = doc.chart.height;
  const grid = new Uint8Array(W * H);
  const runsTop = doc.rows.map((s, y) => { const out = []; let x = 0; for (const [c, n] of parseRuns(s)) { const ci = idx[c]; out.push([ci, n]); grid.fill(ci, y * W + x, y * W + x + n); x += n; } return out; });
  const passes = sequence(doc);
  const rowOfY = Array.from({ length: H }, (_, y) => H - y);
  if (passes) passes.forEach((p, i) => { if (p.gridRow != null) rowOfY[p.gridRow] = i + 1; });
  const cellAspect = doc.gauge && doc.gauge.rows ? doc.gauge.stitches / doc.gauge.rows : 1;
  return { doc, W, H, codes, hex, light, idx, grid, runsTop, passes, cellAspect, rowOfY };
}

export function finishedSize(doc) {
  if (!sizeDerives(doc)) return null;
  const g = doc.gauge, per = g.over.value;
  return { w: +(doc.chart.width / (g.stitches / per)).toFixed(1), h: +(doc.chart.height / (g.rows / per)).toFixed(1), unit: g.over.unit };
}

const pass = (chart, row) => (chart.passes ? chart.passes[row - 1] : null);
export const rowSide = (chart, row) => { const p = pass(chart, row); return (p && p.side) || (row % 2 === 1 ? 'RS' : 'WS'); };
export const yOfRow = (chart, row) => { const p = pass(chart, row); return p && p.gridRow != null ? p.gridRow : chart.H - row; };
export const passLabel = (chart, row) => { const p = pass(chart, row); return (p && p.label) || `Row ${row}`; };

export function workingRuns(chart, row) {
  const p = pass(chart, row);
  if (p) return p.runs.map(r => [chart.idx[r.code], r.count]);
  const runs = chart.runsTop[chart.H - row].slice();
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
    out.push(`${passLabel(chart, r).padStart(9, ' ')} (${rowSide(chart, r)}): ` + runs.map(([c, n]) => `${n} ${chart.codes[c]}`).join(', ') + `  (${runs.reduce((s, x) => s + x[1], 0)} sts)`);
  }
  return out;
}
