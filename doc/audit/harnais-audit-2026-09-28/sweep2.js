(async () => {
  const w = window;
  const all = await (await fetch('http://localhost:54399/__routes2.json')).json();
  const done = JSON.parse(sessionStorage.getItem('__sw2') || '[]');
  const todo = all.filter(p => !done.some(d => d.path === p));
  let cur = null;
  const of = w.fetch;
  w.fetch = async (...a) => { const r = await of(...a); try { const url = typeof a[0] === 'string' ? a[0] : a[0].url; if (r.status >= 400 && cur && !/realtime/.test(url)) { const t = await r.clone().text(); cur.http.push(r.status + ' ' + url.replace('http://localhost:54399','').slice(0,150) + ' :: ' + t.slice(0,200)); } } catch (e) {} return r; };
  const ce = console.error.bind(console);
  console.error = (...a) => { if (cur) cur.console.push(a.map(x => (x && x.message) || String(x)).join(' ').slice(0,300)); ce(...a); };
  const sleep = (ms) => new Promise(r => setTimeout(r, ms));
  for (const path of todo) {
    cur = { path, http: [], console: [], crash: false };
    history.pushState({}, '', path); dispatchEvent(new PopStateEvent('popstate'));
    await sleep(2600);
    const txt = document.body.innerText || '';
    cur.crash = /rencontré une erreur inattendue/.test(txt);
    cur.errorToast = /Une erreur est survenue|Erreur lors du chargement/.test(txt) && !cur.crash;
    cur.len = txt.length;
    done.push(cur); sessionStorage.setItem('__sw2', JSON.stringify(done));
    if (cur.crash) return { crashedAt: path, done: done.length, total: all.length };
  }
  return { finished: true, done: done.length, total: all.length };
})()
