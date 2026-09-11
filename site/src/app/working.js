import { passLabel, rowSide, workingRuns, yOfRow } from './data.js';
import { esc } from './util.js';

export class WorkingMode {
  constructor(chart, hooks) { this.chart = chart; this.hooks = hooks; this.el = null; this.lock = null; this.lockPending = false; }

  open() {
    if (this.el) return;
    const el = document.createElement('div'); el.className = 'working'; el.setAttribute('role', 'dialog'); el.setAttribute('aria-label', 'Working mode'); el.setAttribute('aria-modal', 'true');
    el.innerHTML = `
      <header><div><div class="rownum" id="w-row"></div><div class="sub" id="w-side"></div></div><button id="w-close" aria-label="Close working mode">Close</button></header>
      <div class="strip"><canvas id="w-strip"></canvas></div>
      <div class="wruns" id="w-runs"></div>
      <footer><button id="w-back" aria-label="Back one run">← Back</button><button id="w-done" class="primary">Done ✓</button><button id="w-next" aria-label="Skip to next row">Row →</button></footer>
      <div class="sr" aria-live="polite" id="w-live"></div>`;
    document.body.appendChild(el); document.body.classList.add('in-working'); this.el = el;
    el.querySelector('#w-close').addEventListener('click', () => this.close());
    el.querySelector('#w-done').addEventListener('click', () => this.advance());
    el.querySelector('#w-back').addEventListener('click', () => this.back());
    el.querySelector('#w-next').addEventListener('click', () => { const p = this.hooks.getProgress(); if (p.row >= this.chart.H) { this.announce('Last row'); return; } this.hooks.setRow(p.row + 1, 0, false); this.render(); });
    this.onKey = e => {
      if (e.target.closest('button')) { if (e.key === 'Escape') this.close(); return; }
      if (e.key === ' ' || e.key === 'Enter' || e.key === 'ArrowRight') { e.preventDefault(); this.advance(); }
      if (e.key === 'ArrowLeft') this.back();
      if (e.key === 'Escape') this.close();
    };
    document.addEventListener('keydown', this.onKey);
    this.requestWakeLock();
    this.onVis = () => { if (document.visibilityState === 'visible') this.requestWakeLock(); };
    document.addEventListener('visibilitychange', this.onVis);
    this.render();
    const done = el.querySelector('#w-done'); if (done) done.focus();
  }

  close() {
    if (!this.el) return;
    document.removeEventListener('keydown', this.onKey); document.removeEventListener('visibilitychange', this.onVis);
    if (this.lock) { this.lock.release().catch(() => {}); this.lock = null; }
    this.el.remove(); this.el = null; document.body.classList.remove('in-working');
    const p = this.hooks.getProgress(); this.hooks.setRow(p.row, p.run, true);
    const work = document.getElementById('work'); if (work) work.focus();
  }

  async requestWakeLock() {
    if (this.lock || this.lockPending) return;
    this.lockPending = true;
    try { if ('wakeLock' in navigator) { this.lock = await navigator.wakeLock.request('screen'); this.lock.addEventListener('release', () => { this.lock = null; }); } }
    catch (e) { /* not supported or denied */ }
    finally { this.lockPending = false; }
  }

  advance() {
    const p = this.hooks.getProgress(); const runs = workingRuns(this.chart, p.row);
    if (p.run + 1 >= runs.length) { if (p.row >= this.chart.H) { this.announce('Last row finished'); return; } this.hooks.setRow(p.row + 1, 0, false); this.announce(`Row ${p.row + 1}`); }
    else this.hooks.setRun(p.run + 1);
    this.render();
  }

  back() {
    const p = this.hooks.getProgress();
    if (p.run > 0) this.hooks.setRun(p.run - 1);
    else if (p.row > 1) { const prev = workingRuns(this.chart, p.row - 1); this.hooks.setRow(p.row - 1, Math.max(0, prev.length - 1), false); }
    this.render();
  }

  announce(t) { const live = this.el && this.el.querySelector('#w-live'); if (live) live.textContent = t; }

  render() {
    const { chart } = this; const p = this.hooks.getProgress(); const runs = workingRuns(chart, p.row);
    this.el.querySelector('#w-row').textContent = `${passLabel(chart, p.row)} of ${chart.H}`;
    this.el.querySelector('#w-side').textContent = rowSide(chart, p.row) === 'RS' ? 'Right side · chart reads right → left' : 'Wrong side · chart reads left → right';
    let total = 0;
    this.el.querySelector('#w-runs').innerHTML = runs.map(([c, n], i) => { total += n; return `<span class="chip ${i < p.run ? 'done' : ''} ${i === p.run ? 'current' : ''}" data-i="${esc(i)}" style="background:${esc(chart.hex[c])};color:${chart.light[c] ? '#fff' : '#111'}"><span>${esc(n)} ${esc(chart.codes[c])}</span><small>to ${esc(total)}</small></span>`; }).join('');
    this.el.querySelectorAll('.chip').forEach(ch => ch.addEventListener('click', () => { this.hooks.setRun(+ch.dataset.i); this.render(); }));
    const cur = this.el.querySelector('.chip.current'); if (cur) cur.scrollIntoView({ block: 'nearest' });
    this.drawStrip(p.row);
  }

  drawStrip(row) {
    const { chart } = this; const cv = this.el.querySelector('#w-strip'); const ctx = cv.getContext('2d');
    const cw = 6, ch = 8, rowsAround = 2; const yc = yOfRow(chart, row);
    const y0 = Math.max(0, yc - rowsAround), y1 = Math.min(chart.H, yc + rowsAround + 1);
    cv.width = chart.W * cw; cv.height = (y1 - y0) * ch;
    for (let y = y0; y < y1; y++) { let x = 0; for (const [c, n] of chart.runsTop[y]) { ctx.fillStyle = chart.hex[c]; ctx.fillRect(x * cw, (y - y0) * ch, n * cw, ch); x += n; } }
    const yy = yc - y0; ctx.fillStyle = 'rgba(0,0,0,.35)'; ctx.fillRect(0, 0, cv.width, yy * ch); ctx.fillRect(0, (yy + 1) * ch, cv.width, cv.height - (yy + 1) * ch);
    ctx.strokeStyle = '#D9A21B'; ctx.lineWidth = 2; ctx.strokeRect(1, yy * ch + 1, cv.width - 2, ch - 2);
    ctx.fillStyle = '#D9A21B';
    if (rowSide(chart, row) === 'RS') ctx.fillRect(cv.width - 8, yy * ch, 8, ch); else ctx.fillRect(0, yy * ch, 8, ch);   // marker on the side you start from
  }
}
