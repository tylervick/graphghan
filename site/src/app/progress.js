const key = slug => `graphghan:${slug}:progress`;

export function loadProgress(slug) {
  try { const s = localStorage.getItem(key(slug)); if (!s) return null; const p = JSON.parse(s); return Number.isInteger(p.row) && p.row >= 1 ? { run: 0, ...p } : null; } catch (e) { return null; }
}
export function saveProgress(slug, p) { try { localStorage.setItem(key(slug), JSON.stringify(p)); } catch (e) { /* private mode or blocked storage: progress just isn't remembered */ } }
export function clearProgress(slug) { try { localStorage.removeItem(key(slug)); } catch (e) {} }
export function exportCode(slug, p) { return btoa(unescape(encodeURIComponent(JSON.stringify({ slug, row: p.row, run: p.run || 0 })))).replace(/=+$/, ''); }
export function importCode(code) {
  try { const s = code.trim(); const p = JSON.parse(decodeURIComponent(escape(atob(s + '='.repeat((4 - s.length % 4) % 4))))); return Number.isInteger(p.row) && typeof p.slug === 'string' ? { run: 0, ...p } : null; } catch (e) { return null; }
}
