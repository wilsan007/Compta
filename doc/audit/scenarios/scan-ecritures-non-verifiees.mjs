// Écritures « tirées puis oubliées » : await supabase…insert/update/delete/upsert
// dont le résultat n'est ni déstructuré, ni assigné, ni chaîné à .then/.catch.
//
// `npm run audit:silent` ne les voit pas : il cherche une déstructuration INCOMPLÈTE
// (`const { data } = ...` sans `error`), pas une absence totale de déstructuration.
// Au 23/09/2026 : 29 écritures, dont quatre alimentations de la paie.
//
// Usage, depuis `app/` :  node ../doc/audit/scenarios/scan-ecritures-non-verifiees.mjs
import fs from 'node:fs'; import path from 'node:path'
const files=[]
function walk(d){for(const e of fs.readdirSync(d,{withFileTypes:true})){const p=path.join(d,e.name)
 if(e.isDirectory()){if(!/node_modules|__tests__/.test(p))walk(p)}
 else if(/\.(ts|tsx)$/.test(p)&&!/\.test\.|database-generated/.test(p))files.push(p)}}
for(const r of ['src','supabase/functions']) if(fs.existsSync(r)) walk(r)
let n=0
for(const f of files){
  const lines=fs.readFileSync(f,'utf8').split('\n')
  for(let i=0;i<lines.length;i++){
    const l=lines[i]
    // début d'une expression await supabase… non affectée
    if(!/^\s*await\s+supabase\b/.test(l)) continue
    // lire l'instruction complète (jusqu'à équilibrage des parenthèses)
    let stmt='', depth=0, j=i
    for(;j<lines.length && j<i+40;j++){
      stmt+=lines[j]+'\n'
      for(const ch of lines[j]){ if(ch==='(')depth++; else if(ch===')')depth-- }
      if(depth<=0 && /[)\s;]$/.test(lines[j].trim())) break
    }
    if(!/\.(insert|update|upsert|delete)\s*\(/.test(stmt)) continue
    if(/\.(then|catch)\s*\(/.test(stmt)) continue
    console.log(`${f}:${i+1}\t${l.trim().slice(0,90)}`)
    n++
    i=j
  }
}
console.error(`\n${n} écriture(s) sans aucune vérification d'erreur`)
