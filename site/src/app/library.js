import { loadProgress } from './progress.js';
import { registerServiceWorker } from './pwa.js';
import { esc } from './util.js';

async function main() {
  const box = document.getElementById('cards');
  let patterns;
  try {
    const res = await fetch('patterns/index.json');
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    patterns = await res.json();
  } catch (e) {
    box.innerHTML = '<p class="sub">Could not load the pattern list. Reload to try again.</p>';
    return;
  }
  box.innerHTML = '';
  for (const p of patterns) {
    const prog = loadProgress(p.slug);
    const pct = prog ? Math.min(100, Math.round(((prog.row - 1) / p.height) * 100)) : 0;
    const a = document.createElement('a');
    a.className = 'card';
    a.href = `patterns/${p.slug}/`;
    a.innerHTML = `
      <img src="${esc(p.preview)}" alt="Preview of ${esc(p.title)}">
      <div class="body">
        <h2>${esc(p.title)}</h2>
        <div class="meta"><span>${esc(p.dedication || '')}</span><span>${esc(p.width)} × ${esc(p.height)} ${esc(p.stitch)}</span><span>${esc(p.size_in[0])}″ × ${esc(p.size_in[1])}″</span><span>${esc(p.colors)} colors</span><span>v${esc(p.version)}</span></div>
        <div class="bar-progress" title="${pct}% of rows done"><i style="width:${pct}%"></i></div>
        <div class="sub" style="margin-top:6px">${prog ? `Row ${esc(prog.row)} of ${esc(p.height)}` : 'Not started'}</div>
      </div>`;
    box.appendChild(a);
  }
}

main();
registerServiceWorker();
