import { decodeChart, rowSide, rowStats, workingRuns, writtenLines } from './data.js';
import { ChartView } from './chart.js';
import { loadProgress, saveProgress, exportCode, importCode, clearProgress } from './progress.js';
import { WorkingMode } from './working.js';
import { printTiles } from './print.js';
import { registerServiceWorker } from './pwa.js';
import { esc } from './util.js';

const slug = document.body.dataset.slug;
const $ = id => document.getElementById(id);

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

  // masthead
  $('quote').textContent = doc.quote ? `“${doc.quote}”` : '';
  const specs = [['Chart', `${doc.width} × ${doc.height}`, 'stitches × rows'], ['Finished', `${doc.size_in[0]}″ × ${doc.size_in[1]}″`, 'at design gauge'],
    ['Colors', String(doc.palette.length), doc.yarn_weight], ['Stitch', doc.stitch, '1 cell = 1 stitch'], ['Hook', doc.hook, ''],
    ['Gauge', `${doc.gauge.st_per_in * 4} st × ${doc.gauge.rows_per_in * 4} rows`, '= 4″ blocked'], ['Version', doc.version, doc.variant]];
  $('specs').innerHTML = specs.map(([k, v, s]) => `<div class="spec"><div class="eyebrow">${esc(k)}</div><b>${esc(v)}</b><div class="sub">${esc(s)}</div></div>`).join('');

  // key
  $('keyrows').innerHTML = doc.palette.map(p => `<tr><td><span class="sw" style="background:${esc(p.hex)}"></span><b class="mono">${esc(p.code)}</b></td><td>${esc(p.name)}<div class="sub">${esc(p.use)}</div></td><td>${esc(p.yarn)}</td><td class="num">${esc(doc.stats.counts[p.code].toLocaleString())}</td><td class="num">${esc(doc.stats.yards_est[p.code].toLocaleString())}</td><td class="num">${esc(doc.stats.skeins_364yd[p.code])}</td></tr>`).join('');
  const notes = doc.notes || {};
  $('notes-setup').innerHTML = (notes.setup || []).map(t => `<li>${esc(t)}</li>`).join('');
  $('notes-colors').innerHTML = (notes.colors || []).map(t => `<li>${esc(t)}</li>`).join('');
  $('dl-png').href = `patterns/${slug}/chart.png`; $('dl-rows').href = `patterns/${slug}/written-rows.txt`;
  $('instr-summary').textContent = `All ${doc.height} rows, in working order`;
  $('instr').textContent = writtenLines(chart).join('\n');

  // progress + view
  let progress = loadProgress(slug) || { row: 1, run: 0, updatedAt: null, patternVersion: doc.version };
  const view = new ChartView($('c'), chart, { row: progress.row });
  const scroller = $('scroller');

  function renderRow() {
    const row = progress.row;
    $('rowno').textContent = 'Row ' + row;
    $('rowside').textContent = rowSide(row) === 'RS' ? 'Right side · read chart right → left' : 'Wrong side · read chart left → right';
    const runs = workingRuns(chart, row);
    $('runs').innerHTML = runs.map(([c, n], i) => `<span class="chip ${i < progress.run ? 'done' : ''} ${i === progress.run ? 'current' : ''}" style="background:${esc(chart.hex[c])};color:${chart.light[c] ? '#fff' : '#111'}">${esc(n)} ${esc(chart.codes[c])}</span>`).join('');
    const st = rowStats(chart, row);
    $('rowstats').textContent = `${st.sts} sts · ${st.changes} color changes · ${st.colors} colors in this row`;
    const pct = Math.round(((row - 1) / doc.height) * 100);
    $('progress-summary').textContent = `Row ${row} of ${doc.height} (${pct}% of rows)` + (progress.updatedAt ? `, last worked ${new Date(progress.updatedAt).toLocaleString()}` : '');
  }
  function setRow(row, run = 0, scroll = true) {
    progress = { ...progress, row: Math.min(doc.height, Math.max(1, row)), run, updatedAt: Date.now(), patternVersion: doc.version };
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
  $('c').addEventListener('click', e => { const cell = view.cellAt(e.clientX, e.clientY); if (!cell) return; $('cellinfo').textContent = `Column ${cell.x + 1} of ${doc.width} · Row ${cell.row} · ${doc.palette[cell.ci].name} (${chart.codes[cell.ci]})`; setRow(cell.row, 0, false); });

  $('export').addEventListener('click', async () => { const code = exportCode(slug, progress); try { await navigator.clipboard.writeText(code); alert('Progress code copied. Paste it on the other device.'); } catch (e) { prompt('Copy this progress code:', code); } });
  $('import').addEventListener('click', () => { const code = prompt('Paste the progress code:'); if (!code) return; const p = importCode(code); if (!p || p.slug !== slug) { alert('That code is for a different pattern.'); return; } setRow(p.row, p.run); });
  $('reset').addEventListener('click', () => { if (confirm('Clear progress on this device?')) { clearProgress(slug); setRow(1, 0); } });
  $('print').addEventListener('click', () => printTiles(chart, doc.title));

  const working = new WorkingMode(chart, { getProgress: () => progress, setRow, setRun });
  $('work').addEventListener('click', () => working.open());

  // validation
  (function () {
    const checks = [];
    const bad = chart.runsTop.map((r, i) => [i, r.reduce((s, x) => s + x[1], 0)]).filter(([, s]) => s !== doc.width);
    checks.push([bad.length === 0, `Every row totals ${doc.width} stitches`, bad.length ? 'rows off: ' + bad.map(b => doc.height - b[0]).join(', ') : `${doc.height} rows checked`]);
    const used = new Set(chart.grid); checks.push([used.size === chart.codes.length, `Exactly ${chart.codes.length} colors used`, [...used].map(i => chart.codes[i]).sort().join(' ')]);
    const total = Object.values(doc.stats.counts).reduce((a, b) => a + b, 0); checks.push([total === doc.width * doc.height, `Stitch totals add up to ${total.toLocaleString()}`, `${doc.width} × ${doc.height}`]);
    const ch = doc.stats.color_changes_per_row; checks.push([true, `Color changes per row: mean ${ch.mean}, max ${ch.max}`, `busiest row ${doc.height - ch.per_row.indexOf(ch.max)}`]);
    $('checks').innerHTML = checks.map(([ok, t, s]) => `<div class="check ${ok ? '' : 'fail'}"><b>${ok ? '✓' : '✗'} ${esc(t)}</b><div class="sub">${esc(s)}</div></div>`).join('');
  })();

  fitAndSyncZoom();
  setRow(progress.row, progress.run);
  window.graphghan = { chart, view, setRow, setRun, get progress() { return progress; } };
}

main();
registerServiceWorker();
