import { yOfRow } from './data.js';

const M = 34;   // label margin in px

export class ChartView {
  constructor(canvas, chart, opts = {}) {
    this.cv = canvas; this.ctx = canvas.getContext('2d'); this.chart = chart;
    this.opts = { cw: 6, showGrid: true, showLetters: false, trueProp: false, dimOthers: true, row: 1, ...opts };
  }
  set(patch) { Object.assign(this.opts, patch); this.draw(); }
  get ch() { return this.opts.trueProp ? Math.max(2, Math.round(this.opts.cw * this.chart.cellAspect)) : this.opts.cw; }
  fitWidth(container) { this.opts.cw = Math.max(3, Math.floor((container.clientWidth - 2 * M) / this.chart.W)); this.draw(); return this.opts.cw; }
  scrollToRow(scroller, row) { const y = M + yOfRow(this.chart, row) * this.ch; scroller.scrollTop = Math.max(0, y - scroller.clientHeight / 2); }
  cellAt(clientX, clientY) {
    const r = this.cv.getBoundingClientRect(); const cw = this.opts.cw, ch = this.ch;
    const x = Math.floor((clientX - r.left - M) / cw), y = Math.floor((clientY - r.top - M) / ch);
    if (x < 0 || y < 0 || x >= this.chart.W || y >= this.chart.H) return null;
    return { x, y, row: this.chart.rowOfY[y], ci: this.chart.grid[y * this.chart.W + x] };
  }
  draw() {
    const { cv, ctx, chart } = this; const { cw, showGrid, showLetters, dimOthers, row } = this.opts; const ch = this.ch;
    const { W, H, hex, light, codes, runsTop, grid } = chart;
    cv.width = W * cw + 2 * M; cv.height = H * ch + 2 * M;
    const cs = getComputedStyle(document.documentElement);
    ctx.fillStyle = cs.getPropertyValue('--panel').trim(); ctx.fillRect(0, 0, cv.width, cv.height);
    for (let y = 0; y < H; y++) { let x = 0; for (const [c, n] of runsTop[y]) { ctx.fillStyle = hex[c]; ctx.fillRect(M + x * cw, M + y * ch, n * cw, ch); x += n; } }
    const yy = yOfRow(chart, row);
    if (dimOthers) { const g = cs.getPropertyValue('--ground').trim(); const dark = parseInt(g.slice(1, 3), 16) < 100;
      ctx.fillStyle = dark ? 'rgba(10,16,13,.5)' : 'rgba(255,255,255,.45)'; ctx.fillRect(M, M, W * cw, yy * ch); ctx.fillRect(M, M + (yy + 1) * ch, W * cw, (H - yy - 1) * ch); }
    if (showGrid && cw >= 5) { ctx.strokeStyle = 'rgba(0,0,0,.18)'; ctx.lineWidth = 1; ctx.beginPath();
      for (let x = 0; x <= W; x++) { if (x % 10 === 0) continue; ctx.moveTo(M + x * cw + .5, M); ctx.lineTo(M + x * cw + .5, M + H * ch); }
      for (let y = 0; y <= H; y++) { if (y % 10 === 0) continue; ctx.moveTo(M, M + y * ch + .5); ctx.lineTo(M + W * cw, M + y * ch + .5); }
      ctx.stroke(); }
    if (showGrid) { ctx.strokeStyle = 'rgba(0,0,0,.6)'; ctx.lineWidth = 1; ctx.beginPath();
      for (let x = 0; x <= W; x += 10) { ctx.moveTo(M + x * cw + .5, M); ctx.lineTo(M + x * cw + .5, M + H * ch); }
      ctx.moveTo(M + W * cw + .5, M); ctx.lineTo(M + W * cw + .5, M + H * ch);
      for (let r = 0; r <= H; r += 10) { const y = M + (H - r) * ch + .5; ctx.moveTo(M, y); ctx.lineTo(M + W * cw, y); }
      ctx.moveTo(M, M + .5); ctx.lineTo(M + W * cw, M + .5); ctx.stroke(); }
    if (showLetters && cw >= 12) { ctx.font = `${Math.round(cw * .6)}px "IBM Plex Mono", monospace`; ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
      for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) { const c = grid[y * W + x]; ctx.fillStyle = light[c] ? 'rgba(255,255,255,.85)' : 'rgba(0,0,0,.75)'; ctx.fillText(codes[c], M + x * cw + cw / 2, M + y * ch + ch / 2 + 1); } }
    ctx.strokeStyle = '#D9A21B'; ctx.lineWidth = 3; ctx.strokeRect(M - 1.5, M + yy * ch - 1.5, W * cw + 3, ch + 3);
    ctx.fillStyle = cs.getPropertyValue('--ink').trim(); ctx.font = '11px "IBM Plex Mono", monospace'; ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
    for (let x = 10; x <= W; x += 10) { ctx.fillText(x, M + x * cw - cw / 2, M / 2); ctx.fillText(x, M + x * cw - cw / 2, cv.height - M / 2); }
    ctx.textAlign = 'right'; for (let r = 10; r <= H; r += 10) ctx.fillText(r, M - 4, M + (H - r) * ch + ch / 2);
    ctx.textAlign = 'left'; for (let r = 10; r <= H; r += 10) ctx.fillText(r, M + W * cw + 4, M + (H - r) * ch + ch / 2);
    ctx.textAlign = 'right'; ctx.fillStyle = '#D9A21B'; ctx.font = 'bold 11px "IBM Plex Mono", monospace'; ctx.fillText('▶ ' + row, M - 4, M + yy * ch + ch / 2);
  }
}
