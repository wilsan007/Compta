import fs from 'node:fs'
import { launchBrowser } from '../../scripts/qa/lib/browser.mjs'
const routes = JSON.parse(fs.readFileSync('.qa/audit/dialog-routes.json','utf8'))
const state = process.argv[2] || '.qa/audit/state-0.json'
const CONC = 6
const CREATE = /(^|\s)(\+\s*)?(new|add|create|nouveau|nouvelle|ajouter|créer|creer|record)(\s|$)/i
const SUBMIT = /(save|create|add|submit|enregistrer|créer|ajouter|valider|confirm|ok|générer|generate|run|start|send|envoyer)/i
const b = await launchBrowser()
const results = []
async function one(route) {
  const ctx = await b.newContext({ storageState: state, viewport: { width: 1280, height: 900 } })
  await ctx.addInitScript(() => { try { localStorage.setItem('compta-onboarded','true') } catch {} })
  const page = await ctx.newPage()
  const r = { route, opened:false, emptySubmit:null, filledSubmit:null, writes:[], errors:[], pageErrors:[] }
  page.on('pageerror', e => r.pageErrors.push(String(e).slice(0,160)))
  page.on('console', m => { if (m.type()==='error' && !/websocket|Failed to load resource/i.test(m.text())) r.errors.push(m.text().slice(0,160)) })
  page.on('response', async res => { const rq=res.request(); if (/\/rest\/v1\//.test(res.url()) && rq.method()!=='GET' && rq.method()!=='HEAD') r.writes.push(rq.method()+' '+res.status()+' '+res.url().split('/rest/v1/')[1].slice(0,60)) })
  try {
    await page.goto('http://localhost:5174'+route, { waitUntil:'domcontentloaded', timeout:30000 })
    await page.waitForTimeout(3500)
    const main = page.locator('main, #root').first()
    const btns = page.locator('button:not(aside button):not(nav button)').filter({ hasText: CREATE })
    const n = await btns.count()
    if (!n) { r.note='aucun bouton de création'; return r }
    const url0 = page.url()
    for (let i=0;i<Math.min(n,4) && !r.opened;i++) {
      const bt = btns.nth(i)
      if (!(await bt.isVisible().catch(()=>false))) continue
      await bt.click({ timeout:3000 }).catch(()=>{})
      await page.waitForTimeout(800)
      if (page.url()!==url0) { r.navigated = page.url().replace('http://localhost:5174',''); r.btn=(await bt.innerText().catch(()=>'')).trim().slice(0,40); return r }
      const dlg = page.locator('[role=dialog], [aria-modal=true], div.fixed.inset-0').last()
      if (await dlg.isVisible().catch(()=>false)) { r.opened = true; r.btn=(await bt.innerText().catch(()=>'')).trim().slice(0,40); break }
    }
    if (!r.opened) { r.note='fenêtre non ouverte'; return r }
    const dlg = page.locator('[role=dialog], [aria-modal=true], div.fixed.inset-0').last()
    const submit = async () => {
      let s = dlg.locator('button[type=submit]').first()
      if (!(await s.count())) s = dlg.locator('button').filter({ hasText: SUBMIT }).last()
      if (!(await s.count())) return false
      await s.click({ timeout:3000 }).catch(()=>{}); await page.waitForTimeout(1200); return true
    }
    // 1. soumission à vide
    const w0 = r.writes.length
    const had = await submit()
    const still = await dlg.isVisible().catch(()=>false)
    r.emptySubmit = had ? { stillOpen: still, writes: r.writes.slice(w0), invalid: await dlg.locator(':invalid').count().catch(()=>0), text: (await dlg.innerText().catch(()=>'')).match(/required|obligatoire|requis|invalid|error|erreur|must/i)?.[0] ?? null } : 'pas de bouton de soumission'
    if (!still) return r
    // 2. remplissage générique
    const today = new Date().toISOString().slice(0,10)
    const inputs = dlg.locator('input:not([type=hidden]):not([type=checkbox]):not([type=radio]):not([type=file]):not([readonly]):not([disabled]), textarea')
    const ni = await inputs.count()
    for (let i=0;i<ni;i++) {
      const el = inputs.nth(i); const t = (await el.getAttribute('type'))||'text'
      const v = t==='email'?'audit@test.fr':t==='number'?'10':t==='date'?today:t==='tel'?'0600000000':t==='url'?'https://example.test':t==='password'?'Audit-2026!x':t==='time'?'09:00':t==='datetime-local'?today+'T09:00':t==='month'?today.slice(0,7):'Audit '+i
      await el.fill(v).catch(()=>{})
    }
    const sels = dlg.locator('select:not([disabled])'); const ns = await sels.count()
    for (let i=0;i<ns;i++){ const opts = await sels.nth(i).locator('option').evaluateAll(o=>o.map(x=>({v:x.value,t:x.textContent,d:x.disabled}))); const pick=opts.find(o=>o.v&&!o.d); if(pick) await sels.nth(i).selectOption(pick.v).catch(()=>{}) }
    const w1 = r.writes.length
    const had2 = await submit()
    await page.waitForTimeout(800)
    const still2 = await dlg.isVisible().catch(()=>false)
    const toast = await page.locator('[role=alert], [role=status], .toast, [class*=toast]').allInnerTexts().catch(()=>[])
    r.filledSubmit = had2 ? { stillOpen: still2, writes: r.writes.slice(w1), toast: toast.join(' | ').slice(0,160), dlgText: still2 ? (await dlg.innerText().catch(()=>'')).replace(/\s+/g,' ').slice(-160) : '' } : 'pas de bouton'
  } catch (e) { r.fatal = String(e).slice(0,160) }
  finally { await ctx.close() }
  return r
}
let idx = 0
await Promise.all(Array.from({length:CONC}, async () => { while (idx < routes.length) { const rt = routes[idx++]; const r = await one(rt); results.push(r); process.stdout.write('.') } }))
await b.close()
fs.writeFileSync('.qa/audit/actions-result.json', JSON.stringify(results,null,1))
console.log('\ndone', results.length)
