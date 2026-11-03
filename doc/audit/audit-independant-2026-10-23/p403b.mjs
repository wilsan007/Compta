import fs from 'node:fs'
const rig=JSON.parse(fs.readFileSync('.screen-rig/rig.json','utf8')); const G='http://localhost:54399'; const u=rig.users[0]
const tok=(await (await fetch(G+'/auth/v1/token?grant_type=password',{method:'POST',headers:{'content-type':'application/json',apikey:rig.anonKey},body:JSON.stringify({email:u.email,password:u.password})})).json()).access_token
const call=async(t,b)=>{const r=await fetch(G+'/rest/v1/'+t,{method:'POST',headers:{apikey:rig.anonKey,authorization:'Bearer '+tok,'x-tenant-id':rig.A,'content-type':'application/json'},body:JSON.stringify(b)});const j=await r.json().catch(()=>({}));return r.status+'/'+(j.code||'')}
const names=`tenant_onboarding_state role_permissions business_connectors collective_agreements collective_classifications crm_scoring_rules crm_sequences crm_sequence_steps custom_field_definitions import_column_mappings import_batches payroll_legal_parameters data_import_logs job_postings job_applications stock_transfers stock_transfer_lines uom_categories uoms reorder_rules stock_count_cycles maintenance_records landed_costs landed_cost_receipts webhook_endpoints email_templates`.split(' ')
const bad=[]
for(const t of names){const a=await call(t,{}); const b=await call(t,{tenant_id:rig.A}); const flag=(a.startsWith('403')&&!b.startsWith('403'))?'<<< DÉFAUT':''; if(flag)bad.push(t); console.log(t.padEnd(28),'sans tenant_id:',a.padEnd(10),'avec:',b,flag)}
console.log('\nTables dont la création par l\'écran est refusée faute de tenant_id:',bad.length,bad.join(', '))
