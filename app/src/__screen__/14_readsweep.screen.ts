import { it } from 'vitest'
import fs from 'fs'
import path from 'path'
import { login, A, save } from './rig'
// ⚠️ Correctif du 30/09/2026 : le chemin de l'application était écrit EN DUR
// (`/Users/<poste>/…/app`). Sur le runner de la CI, ce chemin n'existe pas, et le
// balayage mourait sur un `ENOENT: … scandir '/Users/…/app/src/lib/queries'` —
// mesuré sur le run 36766828782, qui a fait échouer le job « Chemin de l'écran ».
// Le chemin se déduit maintenant de la position du fichier (ce dossier est
// `app/src/__screen__`, donc l'application est deux niveaux au-dessus), comme le
// fait déjà `rig.ts` pour le fichier du banc.
const APP = path.resolve(__dirname, '../..')
it('balayage des lecteurs du front', async () => {
  await login(0, A)
  const dir = path.join(APP, 'src/lib/queries')
  const results: any[] = []
  for (const f of fs.readdirSync(dir).filter((x) => x.endsWith('.ts') && !x.includes('index'))) {
    const mod: any = await import(path.join(dir, f))
    for (const [name, fn] of Object.entries(mod)) {
      if (typeof fn !== 'function' || !/^(get|list|fetch|load|search)/.test(name)) continue
      if ((fn as Function).length > 0) { results.push({ f, name, status: 'SKIP_ARGS', arity: (fn as Function).length }); continue }
      try {
        const r = await Promise.race([(fn as Function)(), new Promise((_, rej) => setTimeout(() => rej(new Error('TIMEOUT')), 20000))])
        results.push({ f, name, status: 'OK', n: Array.isArray(r) ? r.length : typeof r })
      } catch (e: any) {
        results.push({ f, name, status: 'ERR', code: e?.code, msg: String(e?.message ?? e).slice(0, 300) })
      }
    }
  }
  save('readsweep.json', results)
})
