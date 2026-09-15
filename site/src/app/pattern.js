import { decodeChart, finishedSize, passLabel, rowSide, rowStats, workingRuns, writtenLines, cellKind, cellNoun } from './data.js';
import { ChartView } from './chart.js';
import { loadProgress, saveProgress, exportCode, importCode, clearProgress } from './progress.js';
import { WorkingMode } from './working.js';
import { printTiles } from './print.js';
import { registerServiceWorker } from './pwa.js';
import { esc } from './util.js';

const slug = document.body.dataset.slug;
const $ = id => document.getElementById(id);
const yarnLabel = y => { y = y || {}; return [y.brand, y.line, y.colorway].filter(Boolean).join(' ') || y.note || ''; };

async function main() {
  let doc;
  try {
    const res = await fetch(`patterns/${slug}/chart.json`);
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    doc = await res.json();
  } catch (e) {
    const viewer = document.querySelector('.viewer');
    if (viewer) viewer.innerHTML = '<p class="sub">Could not load this pattern. Reload to try again.</p>';
    return;
  }
  const chart = decodeChart(doc);
  const P = doc.pattern, C = doc.chart, G = doc.gauge;
  const size = finishedSize(doc);
  const unit = size.unit === 'in' ? '″' : ' cm';

  // masthead
  $('quote').textContent = P.quote ? `“${P.quote}”` : '';
  const specs = [['Chart', `${chart.W} × ${chart.H}`, `${cellNoun(C)} × rows`], ['Finished', `${size.w}${unit} × ${size.h}${unit}`, 'at design gauge'],
    ['Colors', String(doc.palette.length), G.yarn_weight || ''], ['Stitch', G.stitch || '', `1 cell = 1 ${cellKind(C)}`], ['Hook', G.hook || '', ''],
    ['Gauge', `${G.stitches} st × ${G.rows} rows`, `= ${G.over.value}${unit} blocked`], ['Version', P.version, C.variant || '']];
  $('specs').innerHTML = specs.map(([k, v, s]) => `<div class="spec"><div class="eyebrow">${esc(k)}</div><b>${esc(v)}</b><div class="sub">${esc(s)}</div></div>`).join('');

  // key
  // yards_est/skeins_364yd are withheld when a cell is not a stitch (docs/chart-format.md
  // §Cells): render the figure when present, leave the cell blank rather than crash when not.
  const yards = doc.stats.yards_est, skeins = doc.stats.skeins_364yd;
  $('keyrows').innerHTML = doc.palette.map(p => `<tr><td><span class="sw" style="background:${esc(p.hex)}"></span><b class="mono">${esc(p.code)}</b></td><td>${esc(p.name)}<div class="sub">${esc(p.use || '')}</div></td><td>${esc(yarnLabel(p.yarn))}</td><td class="num">${esc(doc.stats.counts[p.code].toLocaleString())}</td><td class="num">${yards ? esc(yards[p.code].toLocaleString()) : ''}</td><td class="num">${skeins ? esc(skeins[p.code]) : ''}</td></tr>`).join('');
  $('instructions').innerHTML = (doc.instructions || []).map(s => `<div class="notes"><h3>${esc(s.title)}</h3><ol>${s.text.split('\n').filter(Boolean).map(t => `<li>${esc(t)}</li>`).join('')}</ol></div>`).join('');
  $('dl-png').href = `patterns/${slug}/chart.png`; $('dl-rows').href = `patterns/${slug}/written-rows.txt`;
  $('instr-summary').textContent = chart.passes ? `All ${chart.H} rows, in working order` : `All ${chart.H} rows (this chart declares no working order; shown bottom to top)`;
  $('instr').textContent = writtenLines(chart).join('\n');

  // progress + view
  let progress = loadProgress(slug) || { row: 1, run: 0, updatedAt: null, patternVersion: P.version };
  const view = new ChartView($('c'), chart, { row: progress.row });
  const scroller = $('scroller');

  function renderRow() {
    const row = progress.row;
    $('rowno').textContent = passLabel(chart, row);
    $('rowside').textContent = rowSide(chart, row) === 'RS' ? 'Right side · read chart right → left' : 'Wrong side · read chart left → right';
    const runs = workingRuns(chart, row);
    $('runs').innerHTML = runs.map(([c, n], i) => `<span class="chip ${i < progress.run ? 'done' : ''} ${i === progress.run ? 'current' : ''}" style="background:${esc(chart.hex[c])};color:${chart.light[c] ? '#fff' : '#111'}">${esc(n)} ${esc(chart.codes[c])}</span>`).join('');
    const st = rowStats(chart, row);
    $('rowstats').textContent = `${st.sts} sts · ${st.changes} color changes · ${st.colors} colors in this row`;
    const pct = Math.round(((row - 1) / chart.H) * 100);
    $('progress-summary').textContent = `Row ${row} of ${chart.H} (${pct}% of rows)` + (progress.updatedAt ? `, last worked ${new Date(progress.updatedAt).toLocaleString()}` : '');
  }
  function setRow(row, run = 0, scroll = true) {
    progress = { ...progress, row: Math.min(chart.H, Math.max(1, row)), run, updatedAt: Date.now(), patternVersion: P.version };
    saveProgress(slug, progress);
    view.set({ row: progress.row });
    if (scroll) view.scrollToRow(scroller, progress.row);
    renderRow();
  }
  function setRun(run) { progress = { ...progress, run, updatedAt: Date.now() }; saveProgress(slug, progress); renderRow(); }

  function fitAndSyncZoom() {
    const zoom = $('zoom');
    const cw = view.fitWidth(scroller);
    const max = zoom.max !== '' ? +zoom.max : cw;
    zoom.value = Math.min(cw, max);
  }
  let resizeTimer = null;
  window.addEventListener('resize', () => { clearTimeout(resizeTimer); resizeTimer = setTimeout(fitAndSyncZoom, 150); });

  $('zoom').addEventListener('input', e => view.set({ cw: +e.target.value }));
  $('grid').addEventListener('change', e => view.set({ showGrid: e.target.checked }));
  $('letters').addEventListener('change', e => { if (e.target.checked && view.opts.cw < 12) { $('zoom').value = 14; view.set({ cw: 14, showLetters: true }); } else view.set({ showLetters: e.target.checked }); });
  $('trueprop').addEventListener('change', e => view.set({ trueProp: e.target.checked }));
  $('dim').addEventListener('change', e => view.set({ dimOthers: e.target.checked }));
  $('fit').addEventListener('click', () => fitAndSyncZoom());
  $('prev').addEventListener('click', () => setRow(progress.row - 1));
  $('next').addEventListener('click', () => setRow(progress.row + 1));
  document.addEventListener('keydown', e => { if (e.target.tagName === 'INPUT' || document.body.classList.contains('in-working')) return; if (e.key === 'ArrowRight' || e.key === 'ArrowUp') setRow(progress.row + 1); if (e.key === 'ArrowLeft' || e.key === 'ArrowDown') setRow(progress.row - 1); });
  $('c').addEventListener('click', e => { const cell = view.cellAt(e.clientX, e.clientY); if (!cell) return; $('cellinfo').textContent = `Column ${cell.x + 1} of ${chart.W} · Row ${cell.row} · ${doc.palette[cell.ci].name} (${chart.codes[cell.ci]})`; setRow(cell.row, 0, false); });

  $('export').addEventListener('click', async () => { const code = exportCode(slug, progress); try { await navigator.clipboard.writeText(code); alert('Progress code copied. Paste it on the other device.'); } catch (e) { prompt('Copy this progress code:', code); } });
  $('import').addEventListener('click', () => { const code = prompt('Paste the progress code:'); if (!code) return; const p = importCode(code); if (!p || p.slug !== slug) { alert('That code is for a different pattern.'); return; } setRow(p.row, p.run); });
  $('reset').addEventListener('click', () => { if (confirm('Clear progress on this device?')) { clearProgress(slug); setRow(1, 0); } });
  $('print').addEventListener('click', () => printTiles(chart, P.title));

  const working = new WorkingMode(chart, { getProgress: () => progress, setRow, setRun });
  $('work').addEventListener('click', () => working.open());

  // validation
  (function () {
    const checks = [];
    const bad = chart.runsTop.map((r, i) => [i, r.reduce((s, x) => s + x[1], 0)]).filter(([, s]) => s !== chart.W);
    checks.push([bad.length === 0, `Every row totals ${chart.W} ${cellNoun(C)}`, bad.length ? 'rows off: ' + bad.map(b => chart.rowOfY[b[0]]).join(', ') : `${chart.H} rows checked`]);
    const used = new Set(chart.grid); checks.push([used.size === chart.codes.length, `Exactly ${chart.codes.length} colors used`, [...used].map(i => chart.codes[i]).sort().join(' ')]);
    const total = Object.values(doc.stats.counts).reduce((a, b) => a + b, 0); checks.push([total === chart.W * chart.H, `Cell totals add up to ${total.toLocaleString()}`, `${chart.W} × ${chart.H}`]);
    const ch = doc.stats.color_changes_per_row; checks.push([true, `Color changes per row: mean ${ch.mean}, max ${ch.max}`, `busiest row ${chart.rowOfY[ch.per_row.indexOf(ch.max)]}`]);
    $('checks').innerHTML = checks.map(([ok, t, s]) => `<div class="check ${ok ? '' : 'fail'}"><b>${ok ? '✓' : '✗'} ${esc(t)}</b><div class="sub">${esc(s)}</div></div>`).join('');
  })();

  fitAndSyncZoom();
  setRow(progress.row, progress.run);
  window.graphghan = { chart, view, setRow, setRun, get progress() { return progress; } };
}

main();
registerServiceWorker();
