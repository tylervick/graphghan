const key = slug => `graphghan:${slug}:progress`;
export function loadProgress(slug) { try { const s = localStorage.getItem(key(slug)); return s ? JSON.parse(s) : null; } catch (e) { return null; } }
export function saveProgress(slug, p) { try { localStorage.setItem(key(slug), JSON.stringify(p)); } catch (e) {} }
export function clearProgress(slug) { try { localStorage.removeItem(key(slug)); } catch (e) {} }
export function exportCode(slug, p) { return btoa(JSON.stringify({ slug, row: p.row, run: p.run })); }
export function importCode(code) { try { return JSON.parse(atob(code.trim())); } catch (e) { return null; } }
