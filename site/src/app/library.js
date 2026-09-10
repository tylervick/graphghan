import { loadProgress } from './progress.js';
import { registerServiceWorker } from './pwa.js';

async function main() {
  const res = await fetch('patterns/index.json');
  const patterns = await res.json();
  const box = document.getElementById('cards');
  box.innerHTML = '';
  for (const p of patterns) {
    const prog = loadProgress(p.slug);
    const pct = prog ? Math.min(100, Math.round(((prog.row - 1) / p.height) * 100)) : 0;
    const a = document.createElement('a');
    a.className = 'card';
    a.href = `patterns/${p.slug}/`;
    a.innerHTML = `
      <img src="${p.preview}" alt="Preview of ${p.title}">
      <div class="body">
        <h2>${p.title}</h2>
        <div class="meta"><span>${p.dedication || ''}</span><span>${p.width} × ${p.height} ${p.stitch}</span><span>${p.size_in[0]}″ × ${p.size_in[1]}″</span><span>${p.colors} colors</span><span>v${p.version}</span></div>
        <div class="bar-progress" title="${pct}% of rows done"><i style="width:${pct}%"></i></div>
        <div class="sub" style="margin-top:6px">${prog ? `Row ${prog.row} of ${p.height}` : 'Not started'}</div>
      </div>`;
    box.appendChild(a);
  }
}

main();
registerServiceWorker();
