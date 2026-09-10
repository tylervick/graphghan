export function loadProgress(slug) { try { const s = localStorage.getItem(`graphghan:${slug}:progress`); return s ? JSON.parse(s) : null; } catch (e) { return null; } }
