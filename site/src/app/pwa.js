function toast(text, actions) {
  const el = document.createElement('div'); el.className = 'toast'; el.innerHTML = `<span>${text}</span>`;
  for (const [label, fn] of actions) { const b = document.createElement('button'); b.textContent = label; b.addEventListener('click', () => { fn(); el.remove(); }); el.appendChild(b); }
  document.body.appendChild(el);
  return el;
}

export function registerServiceWorker() {
  if (!('serviceWorker' in navigator)) return;
  window.addEventListener('load', async () => {
    try {
      const reg = await navigator.serviceWorker.register(new URL('sw.js', document.baseURI));
      const offerReload = worker => toast('A new version is ready.', [['Reload', () => { worker.postMessage('SKIP_WAITING'); }]]);
      if (reg.waiting && navigator.serviceWorker.controller) offerReload(reg.waiting);
      reg.addEventListener('updatefound', () => { const w = reg.installing; if (!w) return; w.addEventListener('statechange', () => { if (w.state === 'installed' && navigator.serviceWorker.controller) offerReload(w); }); });
      let reloading = false;
      navigator.serviceWorker.addEventListener('controllerchange', () => { if (!reloading) { reloading = true; location.reload(); } });
    } catch (e) { /* offline install is a convenience; the page still works */ }
  });
  let deferred = null;
  window.addEventListener('beforeinstallprompt', e => {
    e.preventDefault(); deferred = e;
    try { if (localStorage.getItem('graphghan:install-dismissed')) return; } catch (err) {}
    toast('Install Graphghan for offline use?', [['Install', () => deferred.prompt()], ['Not now', () => { try { localStorage.setItem('graphghan:install-dismissed', '1'); } catch (err) {} }]]);
  });
}
