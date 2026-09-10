import { esc } from './util.js';

export function printTiles(chart, title) {
  const box = document.getElementById('print-tiles'); box.innerHTML = '';
  const { W, H, hex, light, codes, grid } = chart;
  const TW = Math.ceil(W / Math.ceil(W / 64)), TH = Math.ceil(H / Math.ceil(H / 48)), S = 10, m = 26;
  const nx = Math.ceil(W / TW), ny = Math.ceil(H / TH); let t = 0;
  for (let ty = 0; ty < ny; ty++) for (let tx = 0; tx < nx; tx++) {
    t++;
    const rTop = H - ty * TH, rBot = Math.max(1, rTop - TH + 1), c0 = tx * TW + 1, c1 = Math.min(W, c0 + TW - 1);
    const d = document.createElement('div'); d.className = 'tile';
    d.innerHTML = `<h3>${esc(title)} · rows ${esc(rBot)}–${esc(rTop)} · columns ${esc(c0)}–${esc(c1)} (tile ${esc(t)} of ${esc(nx * ny)})</h3>`;
    const k = document.createElement('canvas'); k.width = TW * S + 2 * m; k.height = TH * S + 2 * m; const g = k.getContext('2d');
    g.fillStyle = '#fff'; g.fillRect(0, 0, k.width, k.height);
    for (let y = 0; y < TH; y++) for (let x = 0; x < TW; x++) { const gx = tx * TW + x, gy = ty * TH + y; if (gx >= W || gy >= H) continue; const c = grid[gy * W + gx];
      g.fillStyle = hex[c]; g.fillRect(m + x * S, m + y * S, S, S);
      g.fillStyle = light[c] ? 'rgba(255,255,255,.9)' : 'rgba(0,0,0,.8)'; g.font = '7px monospace'; g.textAlign = 'center'; g.textBaseline = 'middle'; g.fillText(codes[c], m + x * S + S / 2, m + y * S + S / 2 + .5); }
    g.strokeStyle = 'rgba(0,0,0,.5)'; g.lineWidth = 1; g.beginPath();
    for (let x = 0; x <= TW; x++) { if ((tx * TW + x) % 10) continue; g.moveTo(m + x * S + .5, m); g.lineTo(m + x * S + .5, m + TH * S); }
    for (let y = 0; y <= TH; y++) { if ((rTop - y) % 10) continue; g.moveTo(m, m + y * S + .5); g.lineTo(m + TW * S, m + y * S + .5); }
    g.stroke();
    g.fillStyle = '#000'; g.font = '9px monospace'; g.textAlign = 'center';
    for (let x = 0; x < TW; x++) { const gx = tx * TW + x + 1; if (gx % 10) continue; g.fillText(gx, m + x * S + S / 2, m / 2); g.fillText(gx, m + x * S + S / 2, k.height - m / 2); }
    g.textAlign = 'right'; for (let y = 0; y < TH; y++) { const r = rTop - y; if (r % 10) continue; g.fillText(r, m - 3, m + y * S + S / 2); }
    d.appendChild(k); box.appendChild(d);
  }
  document.body.classList.add('printing');
  const done = () => { document.body.classList.remove('printing'); window.removeEventListener('afterprint', done); };
  window.addEventListener('afterprint', done);
  window.print();
  setTimeout(done, 2000);
}
