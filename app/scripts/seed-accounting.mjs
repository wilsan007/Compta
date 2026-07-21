import https from 'https';

const SUPABASE_URL = 'https://ndtaedcgwnaopopugiql.supabase.co';
const SUPABASE_KEY = 'sb_publishable_6WZDE3wBMwc5ildtfy19Nw_pxdPnAZK';
const TID = '00000000-0000-0000-0000-000000000001';
const EMAIL = 'test@test.com';
const PASSWORD = 'tester123';

function fetchUrl(url, options) {
  return new Promise((resolve, reject) => {
    const u = new URL(url);
    const req = https.request(u, options, (res) => {
      let body = '';
      res.on('data', (chunk) => body += chunk);
      res.on('end', () => {
        try { resolve({ status: res.statusCode, data: JSON.parse(body) }); }
        catch { resolve({ status: res.statusCode, data: body }); }
      });
    });
    req.on('error', reject);
    if (options.body) req.write(options.body);
    req.end();
  });
}

async function apiRequest(method, path, body) {
  const options = {
    method,
    headers: {
      'apikey': SUPABASE_KEY,
      'Content-Type': 'application/json',
      'Prefer': 'return=representation',
    },
  };
  if (TOKEN) options.headers['Authorization'] = `Bearer ${TOKEN}`;
  if (body) options.body = JSON.stringify(body);
  return fetchUrl(`${SUPABASE_URL}${path}`, options);
}

let TOKEN = null;

async function login() {
  const res = await fetchUrl(`${SUPABASE_URL}/auth/v1/token?grant_type=password`, {
    method: 'POST',
    headers: { 'apikey': SUPABASE_KEY, 'Content-Type': 'application/json' },
    body: JSON.stringify({ email: EMAIL, password: PASSWORD }),
  });
  if (res.data.access_token) {
    TOKEN = res.data.access_token;
    console.log('✓ Login OK');
  } else {
    throw new Error('Login failed: ' + JSON.stringify(res.data));
  }
}

async function insertOne(table, record) {
  const res = await apiRequest('POST', `/rest/v1/${table}`, record);
  if (res.status >= 400) {
    console.error(`✗ ${table}: ${JSON.stringify(res.data)}`);
    return null;
  }
  return Array.isArray(res.data) ? res.data[0] : res.data;
}

async function main() {
  await login();

  // === 1. JOURNAUX ===
  console.log('\n=== 1. JOURNAUX ===');
  const journals = [
    { code: 'VT', name: 'Ventes', type: 'sale', account_counterpart: '411000', status: 'active', locked: false, tenant_id: TID, access_level: 'all' },
    { code: 'BQ', name: 'Banque', type: 'bank', account_counterpart: '512000', status: 'active', locked: false, tenant_id: TID, access_level: 'all' },
    { code: 'OD', name: 'Opérations diverses', type: 'general', status: 'active', locked: false, tenant_id: TID, access_level: 'all' },
    { code: 'AN', name: 'À-nouveau', type: 'general', status: 'active', locked: false, tenant_id: TID, access_level: 'all' },
  ];
  for (const j of journals) {
    const r = await insertOne('journals', j);
    if (r) console.log(`  ✓ Journal ${j.code} — ${j.name}`);
  }

  // === 2. COMPTES MANQUANTS ===
  console.log('\n=== 2. COMPTES COMPTABLES ===');
  const accounts = [
    { code: '401000', name: 'Fournisseurs', type: 'liability', balance: 0, tenant_id: TID },
    { code: '411000', name: 'Clients', type: 'asset', balance: 0, tenant_id: TID },
    { code: '512000', name: 'Banque', type: 'asset', balance: 50000, tenant_id: TID },
    { code: '530000', name: 'Caisse', type: 'asset', balance: 5000, tenant_id: TID },
    { code: '607000', name: 'Achats de marchandises', type: 'expense', balance: 0, tenant_id: TID },
    { code: '707000', name: 'Ventes de marchandises', type: 'income', balance: 0, tenant_id: TID },
    { code: '445660', name: 'TVA déductible', type: 'liability', balance: 0, tenant_id: TID },
    { code: '445710', name: 'TVA collectée', type: 'liability', balance: 0, tenant_id: TID },
    { code: '641000', name: 'Salaires brut', type: 'expense', balance: 0, tenant_id: TID },
    { code: '645000', name: 'Charges sociales', type: 'expense', balance: 0, tenant_id: TID },
    { code: '431000', name: 'Sécurité sociale', type: 'liability', balance: 0, tenant_id: TID },
    { code: '661000', name: 'Charges financières', type: 'expense', balance: 0, tenant_id: TID },
    { code: '761000', name: 'Produits financiers', type: 'income', balance: 0, tenant_id: TID },
  ];
  for (const a of accounts) {
    const r = await insertOne('chart_accounts', a);
    if (r) console.log(`  ✓ Compte ${a.code} — ${a.name}`);
  }

  // === 3. TIERS ===
  console.log('\n=== 3. COMPTES TIERS ===');
  const tiers = [
    { code: '411001', name: 'Client Alpha SARL', type: 'customer', account_general_code: '411000', balance: 15000, tenant_id: TID },
    { code: '411002', name: 'Client Beta SA', type: 'customer', account_general_code: '411000', balance: 8500, tenant_id: TID },
    { code: '411003', name: 'Client Gamma EURL', type: 'customer', account_general_code: '411000', balance: 3200, tenant_id: TID },
    { code: '401001', name: 'Fournisseur Delta SARL', type: 'supplier', account_general_code: '401000', balance: -12000, tenant_id: TID },
    { code: '401002', name: 'Fournisseur Epsilon SA', type: 'supplier', account_general_code: '401000', balance: -7500, tenant_id: TID },
    { code: '401003', name: 'Fournisseur Zeta SARL', type: 'supplier', account_general_code: '401000', balance: -3200, tenant_id: TID },
  ];
  for (const t of tiers) {
    const r = await insertOne('third_party_accounts', t);
    if (r) console.log(`  ✓ Tiers ${t.code} — ${t.name}`);
  }

  // === 4. CLIENTS & FOURNISSEURS (pour payment delays) ===
  console.log('\n=== 4. CLIENTS ===');
  const customers = [
    { name: 'Client Alpha SARL', email: 'contact@alpha.com', phone: '+33 1 23 45 67 89', address: '12 rue de la Paix, Paris', siret: '12345678900012', tenant_id: TID },
    { name: 'Client Beta SA', email: 'contact@beta.com', phone: '+33 1 98 76 54 32', address: '45 av des Champs, Paris', siret: '98765432100021', tenant_id: TID },
    { name: 'Client Gamma EURL', email: 'contact@gamma.com', phone: '+33 1 55 44 33 22', address: '78 bd Voltaire, Lyon', siret: '55544433300044', tenant_id: TID },
  ];
  const customerIds = [];
  for (const c of customers) {
    const r = await insertOne('customers', c);
    if (r) { customerIds.push(r.id); console.log(`  ✓ Client ${c.name} (${r.id.slice(0,8)})`); }
  }

  console.log('\n=== 5. FOURNISSEURS ===');
  const suppliers = [
    { name: 'Fournisseur Delta SARL', email: 'contact@delta.com', phone: '+33 4 11 22 33 44', address: '23 rue du Commerce, Marseille', siret: '11122233300044', tenant_id: TID },
    { name: 'Fournisseur Epsilon SA', email: 'contact@epsilon.com', phone: '+33 4 55 66 77 88', address: '56 rue Nationale, Lille', siret: '44455566600077', tenant_id: TID },
  ];
  const supplierIds = [];
  for (const s of suppliers) {
    const r = await insertOne('suppliers', s);
    if (r) { supplierIds.push(r.id); console.log(`  ✓ Fournisseur ${s.name} (${r.id.slice(0,8)})`); }
  }

  // === 6. FACTURES (pour payment delays) ===
  console.log('\n=== 6. FACTURES ===');
  const invoices = [
    { number: 'FAC-2024-001', customer_id: customerIds[0], date: '2024-03-15', due_date: '2024-04-14', total: 12000, amount_paid: 12000, status: 'paid', tenant_id: TID, updated_at: '2024-04-20T10:00:00Z' },
    { number: 'FAC-2024-002', customer_id: customerIds[1], date: '2024-05-10', due_date: '2024-06-09', total: 8500, amount_paid: 8500, status: 'paid', tenant_id: TID, updated_at: '2024-06-25T10:00:00Z' },
    { number: 'FAC-2024-003', customer_id: customerIds[0], date: '2024-07-01', due_date: '2024-07-31', total: 5500, amount_paid: 5500, status: 'paid', tenant_id: TID, updated_at: '2024-08-10T10:00:00Z' },
    { number: 'FAC-2024-004', customer_id: customerIds[2], date: '2024-09-05', due_date: '2024-10-05', total: 3200, amount_paid: 3200, status: 'paid', tenant_id: TID, updated_at: '2024-10-20T10:00:00Z' },
    { number: 'FAC-2024-005', customer_id: customerIds[1], date: '2024-11-12', due_date: '2024-12-12', total: 7800, amount_paid: 7800, status: 'paid', tenant_id: TID, updated_at: '2024-12-28T10:00:00Z' },
  ];
  for (const inv of invoices) {
    const r = await insertOne('invoices', inv);
    if (r) console.log(`  ✓ Facture ${inv.number} — ${inv.total}€ (paid)`);
  }

  // === 7. ÉCRITURES COMPTABLES ===
  console.log('\n=== 7. ÉCRITURES COMPTABLES ===');

  async function createEntry(number, date, description, journalCode, lines) {
    const totalDebit = lines.reduce((s, l) => s + l.debit, 0);
    const totalCredit = lines.reduce((s, l) => s + l.credit, 0);
    if (Math.abs(totalDebit - totalCredit) > 0.01) {
      console.error(`  ✗ ${number}: non équilibré D=${totalDebit} C=${totalCredit}`);
      return null;
    }
    const entryData = {
      number, date, description, journal_code: journalCode,
      status: 'posted', total_debit: totalDebit, total_credit: totalCredit,
      tenant_id: TID, piece_number: number,
    };
    const je = await insertOne('journal_entries', entryData);
    if (!je) return null;

    for (let i = 0; i < lines.length; i++) {
      const l = lines[i];
      await insertOne('journal_lines', {
        journal_id: je.id, account_code: l.account_code, account_name: l.account_name || '',
        account_general: l.account_general || null, account_tiers: l.account_tiers || null,
        debit: l.debit, credit: l.credit, description: l.description || '',
        line_order: i, tenant_id: TID,
      });
    }
    console.log(`  ✓ ${number} (${journalCode}) — D=${totalDebit} C=${totalCredit} [${lines.length} lignes]`);
    return je;
  }

  // À-nouveau (ouverture)
  await createEntry('AN-2024-001', '2024-01-01', 'À-nouveau ouverture 2024', 'AN', [
    { account_code: '512000', account_name: 'Banque', debit: 50000, credit: 0 },
    { account_code: '530000', account_name: 'Caisse', debit: 5000, credit: 0 },
    { account_code: '101000', account_name: 'Capital social', debit: 0, credit: 55000 },
  ]);

  // Achat marchandises (ACH)
  await createEntry('ACH-2024-001', '2024-02-15', 'Achat marchandises - Fournisseur Delta', 'ACH', [
    { account_code: '607000', account_name: 'Achats de marchandises', debit: 10000, credit: 0 },
    { account_code: '445660', account_name: 'TVA déductible', debit: 2000, credit: 0 },
    { account_code: '401001', account_name: 'Fournisseur Delta SARL', account_general: '401000', account_tiers: '401001', debit: 0, credit: 12000 },
  ]);

  await createEntry('ACH-2024-002', '2024-04-20', 'Achat marchandises - Fournisseur Epsilon', 'ACH', [
    { account_code: '607000', account_name: 'Achats de marchandises', debit: 7500, credit: 0 },
    { account_code: '445660', account_name: 'TVA déductible', debit: 1500, credit: 0 },
    { account_code: '401002', account_name: 'Fournisseur Epsilon SA', account_general: '401000', account_tiers: '401002', debit: 0, credit: 9000 },
  ]);

  // Ventes (VT)
  await createEntry('VT-2024-001', '2024-03-15', 'Vente marchandises - Client Alpha', 'VT', [
    { account_code: '411001', account_name: 'Client Alpha SARL', account_general: '411000', account_tiers: '411001', debit: 14400, credit: 0 },
    { account_code: '707000', account_name: 'Ventes de marchandises', debit: 0, credit: 12000 },
    { account_code: '445710', account_name: 'TVA collectée', debit: 0, credit: 2400 },
  ]);

  await createEntry('VT-2024-002', '2024-05-10', 'Vente marchandises - Client Beta', 'VT', [
    { account_code: '411002', account_name: 'Client Beta SA', account_general: '411000', account_tiers: '411002', debit: 10200, credit: 0 },
    { account_code: '707000', account_name: 'Ventes de marchandises', debit: 0, credit: 8500 },
    { account_code: '445710', account_name: 'TVA collectée', debit: 0, credit: 1700 },
  ]);

  await createEntry('VT-2024-003', '2024-07-01', 'Vente marchandises - Client Alpha (2)', 'VT', [
    { account_code: '411001', account_name: 'Client Alpha SARL', account_general: '411000', account_tiers: '411001', debit: 6600, credit: 0 },
    { account_code: '707000', account_name: 'Ventes de marchandises', debit: 0, credit: 5500 },
    { account_code: '445710', account_name: 'TVA collectée', debit: 0, credit: 1100 },
  ]);

  // Paiement banque (BQ)
  await createEntry('BQ-2024-001', '2024-04-20', 'Règlement Client Alpha', 'BQ', [
    { account_code: '512000', account_name: 'Banque', debit: 14400, credit: 0 },
    { account_code: '411001', account_name: 'Client Alpha SARL', account_general: '411000', account_tiers: '411001', debit: 0, credit: 14400 },
  ]);

  await createEntry('BQ-2024-002', '2024-06-25', 'Règlement Client Beta', 'BQ', [
    { account_code: '512000', account_name: 'Banque', debit: 10200, credit: 0 },
    { account_code: '411002', account_name: 'Client Beta SA', account_general: '411000', account_tiers: '411002', debit: 0, credit: 10200 },
  ]);

  await createEntry('BQ-2024-003', '2024-05-01', 'Règlement Fournisseur Delta', 'BQ', [
    { account_code: '401001', account_name: 'Fournisseur Delta SARL', account_general: '401000', account_tiers: '401001', debit: 12000, credit: 0 },
    { account_code: '512000', account_name: 'Banque', debit: 0, credit: 12000 },
  ]);

  // Salaires (OD)
  await createEntry('OD-2024-001', '2024-03-31', 'Salaires mars 2024', 'OD', [
    { account_code: '641000', account_name: 'Salaires brut', debit: 25000, credit: 0 },
    { account_code: '645000', account_name: 'Charges sociales', debit: 10000, credit: 0 },
    { account_code: '431000', account_name: 'Sécurité sociale', debit: 0, credit: 10000 },
    { account_code: '512000', account_name: 'Banque', debit: 0, credit: 25000 },
  ]);

  // === 8. TVS (déjà testé, on garde les seed) ===
  console.log('\n=== 8. TVS (vérification) ===');
  const tvsRes = await apiRequest('GET', `/rest/v1/tvs_declarations?select=vehicle_registration,amount_total&tenant_id=eq.${TID}`);
  if (Array.isArray(tvsRes.data)) {
    console.log(`  ${tvsRes.data.length} déclarations TVS déjà présentes`);
  }

  // === 9. CURRENCY REVALUATION (vérification) ===
  console.log('\n=== 9. CURRENCY REVALUATION (vérification) ===');
  const crRes = await apiRequest('GET', `/rest/v1/currency_revaluations?select=currency,gain_loss&tenant_id=eq.${TID}`);
  if (Array.isArray(crRes.data)) {
    console.log(`  ${crRes.data.length} réévaluations déjà présentes`);
  }

  console.log('\n=== TERMINÉ ===');
  console.log('Données insérées: journaux, comptes, tiers, clients, fournisseurs, factures, écritures comptables');
}

main().catch(err => { console.error('Erreur:', err); process.exit(1); });
