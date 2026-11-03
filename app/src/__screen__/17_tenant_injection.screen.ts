// Audit indépendant du 23/10/2026 — « création refusée par l'écran sur ~22 tables ».
//
// `ti()` ne pose `tenant_id` que pour les tables de TENANT_TABLES ; ces tables n'y étaient
// pas, n'ont ni défaut ni déclencheur, et la RLS exige `tenant_id = current_tenant_id()` :
// toute création depuis l'écran était refusée (403).
//
// Ce scénario appelle les VRAIES fonctions de requête des écrans à travers le vrai client →
// passerelle → PostgREST → RLS réelle, puis CONSTATE par lecture directe : la ligne existe,
// elle porte la société A, et la société B ne la voit pas. Le garde statique
// `scripts/check-tenant-injection.mjs` voit le registre ; celui-ci voit l'effet.
// Joué APRÈS 02 : il lit un article et une réception de la société A.
import { it } from 'vitest'
import { login, A, B, sql, check, attempt, save, findings } from './rig'

type Cree = { table: string; id: string | null; err?: string }

// Le jeu de test ne remplit que les colonnes utiles : on l'accepte comme premier
// argument de la vraie fonction de requête, sans `any`.
const arg = <F extends (...a: never[]) => unknown>(_fn: F, v: Record<string, unknown>) => v as Parameters<F>[0]

it('Création par l\'écran dans les 26 tables de p403b.mjs (registre + pose explicite)', async () => {
  const stamp = String(Date.now()).slice(-8)
  const sb = await login(0, A)
  const core = await import('@/lib/queries/core')
  const stock = await import('@/lib/queries/stock')
  const crmSeq = await import('@/lib/queries/crmSequences')
  const crmScore = await import('@/lib/queries/crmScoring')
  const cf = await import('@/lib/queries/customFields')
  const rec = await import('@/lib/queries/recruitment')
  const ccn = await import('@/lib/queries/collectiveAgreements')
  const imp = await import('@/lib/queries/imports')
  const prod = await import('@/lib/queries/production')
  const bc = await import('@/lib/queries/businessConnectors')
  const admin = await import('@/lib/queries/admin')
  const payroll = await import('@/lib/queries/payroll')

  // Prérequis LUS, jamais fabriqués. Un rôle de société n'a aucun écran de création : il est
  // posé par SQL, et c'est le seul état préparé hors du chemin de l'écran.
  const produit = (await sql(`select id from products where tenant_id=$1 order by created_at limit 1`, [A]))[0]
  const reception = (await sql(`select id from goods_receipts where tenant_id=$1 order by created_at limit 1`, [A]))[0]
  check('TI00', 'prérequis : un article et une réception existent pour la société A', !!produit && !!reception, { produit: produit?.id, reception: reception?.id })
  if (!produit || !reception) { save('s17.json', findings); return }
  const role = (await sql(`insert into tenant_roles (tenant_id, name) values ($1, $2) returning id`, [A, `Role audit ${stamp}`]))[0]

  const crees: Cree[] = []
  // On ne croit JAMAIS la valeur de retour d'un écran (setRolePermission avale l'erreur) :
  // on relit la base.
  async function creer(table: string, fn: () => Promise<unknown>, relire: string, params: unknown[]) {
    const r = await attempt(fn)
    const row = (await sql(relire, params))[0] as { id: string; tenant_id: string } | undefined
    crees.push({ table, id: row?.id ?? null, err: r.err })
    check(`TI-${table}`, `${table} : créé par l'écran, posé sur la société A`,
      !!row && row.tenant_id === A, row ? { tenant: row.tenant_id === A ? 'A' : row.tenant_id } : { err: r.err ?? 'aucune ligne' })
  }

  // ---------- Stock (9 tables) ----------
  const w1 = await attempt(() => stock.createWarehouse(arg(stock.createWarehouse, { code: `AU1${stamp}`, name: 'Dépôt audit 1', address: null, city: null, postal_code: null, country: 'France', active: true })))
  const w2 = await attempt(() => stock.createWarehouse(arg(stock.createWarehouse, { code: `AU2${stamp}`, name: 'Dépôt audit 2', address: null, city: null, postal_code: null, country: 'France', active: true })))
  const wa = w1.val as { id?: string } | null, wb = w2.val as { id?: string } | null
  check('TI-warehouses', 'prérequis des transferts : deux dépôts créés (table déjà dans le registre)', w1.ok && w2.ok, w1.err ?? w2.err ?? 'ok')

  const num = `TR-AUD-${stamp}`
  await creer('stock_transfers', () => stock.createStockTransfer(arg(stock.createStockTransfer, { transfer_number: num, from_warehouse_id: wa?.id, to_warehouse_id: wb?.id, status: 'pending' })),
    `select id, tenant_id from stock_transfers where transfer_number=$1`, [num])
  const tr = (await sql(`select id from stock_transfers where transfer_number=$1`, [num]))[0]
  await creer('stock_transfer_lines', () => stock.createStockTransferLine(arg(stock.createStockTransferLine, { transfer_id: tr?.id, product_id: produit.id, quantity: 2 })),
    `select id, tenant_id from stock_transfer_lines where transfer_id=$1`, [tr?.id])

  const catName = `Catégorie audit ${stamp}`
  await creer('uom_categories', () => stock.createUomCategory(arg(stock.createUomCategory, { name: catName })),
    `select id, tenant_id from uom_categories where name=$1`, [catName])
  const cat = (await sql(`select id from uom_categories where name=$1`, [catName]))[0]
  await creer('uoms', () => stock.createUom(arg(stock.createUom, { code: `U${stamp}`, name: `Unité audit ${stamp}`, category_id: cat?.id })),
    `select id, tenant_id from uoms where code=$1`, [`U${stamp}`])

  await creer('reorder_rules', () => stock.createReorderRule(arg(stock.createReorderRule, { product_id: produit.id, min_quantity: 5, max_quantity: 50 })),
    `select id, tenant_id from reorder_rules where product_id=$1 order by created_at desc limit 1`, [produit.id])
  await creer('stock_count_cycles', () => stock.createStockCountCycle(arg(stock.createStockCountCycle, { product_id: produit.id })),
    `select id, tenant_id from stock_count_cycles where product_id=$1 order by created_at desc limit 1`, [produit.id])
  await creer('maintenance_records', () => stock.createMaintenanceRecord(arg(stock.createMaintenanceRecord, { maintenance_date: '2026-10-23', status: 'planned', notes: `audit ${stamp}` })),
    `select id, tenant_id from maintenance_records where notes=$1`, [`audit ${stamp}`])
  const fact = `FA-AUD-${stamp}`
  await creer('landed_costs', () => stock.createLandedCost(arg(stock.createLandedCost, { invoice_number: fact, supplier_id: null, total_amount: 120, distribution_method: 'value', status: 'pending' })),
    `select id, tenant_id from landed_costs where invoice_number=$1`, [fact])
  const lc = (await sql(`select id from landed_costs where invoice_number=$1`, [fact]))[0]
  await creer('landed_cost_receipts', () => stock.addLandedCostReceipt(lc?.id, reception.id),
    `select id, tenant_id from landed_cost_receipts where landed_cost_id=$1`, [lc?.id])

  // ---------- CRM (4 tables) ----------
  const seqName = `Séquence audit ${stamp}`
  await creer('crm_sequences', () => crmSeq.createCrmSequence({ name: seqName }),
    `select id, tenant_id from crm_sequences where name=$1`, [seqName])
  const seq = (await sql(`select id from crm_sequences where name=$1`, [seqName]))[0]
  await creer('crm_sequence_steps', () => crmSeq.createCrmSequenceStep({ sequenceId: seq?.id, stepOrder: 1, delayDays: 0, channel: 'email' }),
    `select id, tenant_id from crm_sequence_steps where sequence_id=$1`, [seq?.id])
  const scoreName = `Règle audit ${stamp}`
  await creer('crm_scoring_rules', () => crmScore.createCrmScoringRule({ name: scoreName, field: 'status', operator: 'equals', value: 'qualified', points: 10 }),
    `select id, tenant_id from crm_scoring_rules where name=$1`, [scoreName])
  const fieldKey = `champ_audit_${stamp}`
  await creer('custom_field_definitions', () => cf.createCustomFieldDefinition({ module: 'crm', entity: 'customer', fieldKey, label: 'Champ audit', fieldType: 'text' }),
    `select id, tenant_id from custom_field_definitions where field_key=$1`, [fieldKey])

  // ---------- RH (4 tables) ----------
  const poste = `Poste audit ${stamp}`
  await creer('job_postings', () => rec.createJobPosting({ title: poste, contractType: 'cdi' }),
    `select id, tenant_id from job_postings where title=$1`, [poste])
  const jp = (await sql(`select id from job_postings where title=$1`, [poste]))[0]
  const candidat = `Candidat audit ${stamp}`
  await creer('job_applications', () => rec.createJobApplication({ postingId: jp?.id, candidateName: candidat }),
    `select id, tenant_id from job_applications where candidate_name=$1`, [candidat])
  const idcc = `9${stamp}`
  await creer('collective_agreements', () => ccn.createCollectiveAgreement({ idccCode: idcc, name: `Convention audit ${stamp}`, applicationDate: '2026-01-01' }),
    `select id, tenant_id from collective_agreements where idcc_code=$1`, [idcc])
  const ca = (await sql(`select id from collective_agreements where idcc_code=$1`, [idcc]))[0]
  await creer('collective_classifications', () => ccn.createCollectiveClassification({ agreementId: ca?.id, coefficient: 100, minimumMonthlySalary: 1800 }),
    `select id, tenant_id from collective_classifications where agreement_id=$1`, [ca?.id])

  // ---------- Paramètres et système (6 tables) ----------
  await creer('role_permissions', () => admin.setRolePermission(role.id, 'sales.read'),
    `select id, tenant_id from role_permissions where role_id=$1`, [role.id])
  const mapName = `Mapping audit ${stamp}`
  await creer('import_column_mappings', () => imp.saveColumnMapping(mapName, 'customers', { Nom: 'name' }),
    `select id, tenant_id from import_column_mappings where name=$1`, [mapName])
  const fichier = `audit-${stamp}.csv`
  await creer('import_batches', () => imp.createImportBatch('customers', fichier, 10),
    `select id, tenant_id from import_batches where file_name=$1`, [fichier])
  const journal = `journal-${stamp}.csv`
  await creer('data_import_logs', () => prod.logDataImport('customers', journal, 10, 10, 0, 'completed'),
    `select id, tenant_id from data_import_logs where file_name=$1`, [journal])
  const conn = `Connecteur audit ${stamp}`
  await creer('business_connectors', () => bc.createBusinessConnector({ name: conn, connectorType: 'webhook', baseUrl: 'https://example.test/hook', authType: 'none' }),
    `select id, tenant_id from business_connectors where name=$1`, [conn])
  // EmailTemplatesPage : l'insertion vit dans le composant ; on rejoue sa charge utile exacte.
  const tplKey = `audit_${stamp}`
  await creer('email_templates', async () => {
    const tid = await core.getTenantId()
    const { error } = await sb.from('email_templates').insert(core.ti({ template_key: tplKey, subject: 'Sujet audit', body_html: '<p>Corps</p>', body_text: null, variables: [], locale: 'fr' }, 'email_templates', tid))
    if (error) throw error
  }, `select id, tenant_id from email_templates where template_key=$1`, [tplKey])

  // ---------- les 3 tables à pose EXPLICITE de tenant_id (hors registre) ----------
  // Le registre n'est pas le seul moyen d'injecter le tenant : ces trois écritures le posent
  // elles-mêmes, et le garde statique le reconnaît comme couvert. La preuve des 26 tables de
  // p403b.mjs exige de les exercer aussi :
  //   - webhook_endpoints        : insert du composant ApiWebhooksPage.tsx:161 (pose explicite
  //                                `tenant_id: tid` → re-jouer le payload exact) ;
  //   - tenant_onboarding_state  : updateOnboardingStep() (lib/queries/admin.ts:61, upsert) ;
  //   - payroll_legal_parameters : saveCompanyPayrollParameters() (lib/queries/payroll.ts:885,
  //                                upsert, pose explicite + lignes légales à tenant_id NULL).
  const tidExp = await core.getTenantId()
  await creer('webhook_endpoints', async () => {
    const { error } = await sb.from('webhook_endpoints').insert({ name: `Webhook audit ${stamp}`, url: 'https://hooks.example.com/ti', active_events: ['*'], tenant_id: tidExp })
    if (error) throw error
  }, `select id, tenant_id from webhook_endpoints where name=$1`, [`Webhook audit ${stamp}`])
  await creer('tenant_onboarding_state', async () => {
    await admin.updateOnboardingStep('step_stock_valuation', true)
  }, `select id, tenant_id from tenant_onboarding_state where tenant_id=$1`, [A])
  await creer('payroll_legal_parameters', async () => {
    await payroll.saveCompanyPayrollParameters(false, 1.25, '2026-10')
  }, `select id, tenant_id from payroll_legal_parameters where tenant_id=$1 and code='TAUX_ATMP' and valid_from='2026-10-01'`, [A])

  // ---------- Cloisonnement : la société B ne voit aucune de ces lignes ----------
  const creees = crees.filter((c) => c.id)
  const parTable = new Map<string, string[]>()
  for (const c of creees) parTable.set(c.table, [...(parTable.get(c.table) ?? []), c.id as string])
  await login(1, B)
  let vues = 0
  const fuites: string[] = []
  for (const [table, ids] of parTable) {
    const { data } = await sb.from(table).select('id').in('id', ids)
    if (data?.length) { vues += data.length; fuites.push(table) }
  }
  check('TI-iso', `cloisonnement : la société B ne lit aucune des ${creees.length} lignes créées par A`, creees.length > 0 && vues === 0, { lignes: creees.length, vues, fuites })
  check('TI-total', 'les 26 tables de p403b.mjs acceptent toutes une création par l\'écran (23 via le registre, 3 à pose explicite)', creees.length === 26, { creees: creees.length, absentes: crees.filter((c) => !c.id).map((c) => c.table) })
  save('s17.json', findings)
})
