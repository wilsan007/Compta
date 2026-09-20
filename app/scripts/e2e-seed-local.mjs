import pg from 'pg'
import { readFileSync } from 'fs'

const client = new pg.Client({
  host: '127.0.0.1',
  port: 54322,
  user: 'postgres',
  password: 'postgres',
  database: 'postgres',
})

await client.connect()

async function run(file, label) {
  const sql = readFileSync(file, 'utf8')
  await client.query(sql)
  console.log(`OK: ${label}`)
}

try {
  await run('sql/02_bootstrap_tenant.sql', 'bootstrap function created')

  // Patch: currencies est devenu un catalogue global (tenant_id NULL, unique global sur code)
  let bootstrap = readFileSync('sql/02_bootstrap_tenant.sql', 'utf8')
  bootstrap = bootstrap.replace(
    /INSERT INTO currencies \(code, name, symbol, exchange_rate, tenant_id\)[\s\S]*?ON CONFLICT \(tenant_id, code\) DO NOTHING;/,
    () => `INSERT INTO currencies (code, name, symbol, exchange_rate, tenant_id)
  SELECT v.code, v.name, v.symbol, v.rate, NULL FROM (VALUES
    ('EUR', 'Euro',           E'\\u20AC', 1.0),
    ('USD', 'Dollar US',      '$', 1.08),
    ('GBP', 'Livre Sterling', E'\\u00A3', 0.85)
  ) AS v(code, name, symbol, rate)
  WHERE NOT EXISTS (SELECT 1 FROM currencies c WHERE c.code = v.code);`
  )
  await client.query(bootstrap)
  await client.query(`SELECT bootstrap_tenant('a0000000-0000-0000-0000-000000000001')`)
  console.log('OK: bootstrap_tenant(a000...001)')

  let seed = readFileSync('sql/seed_phase1.sql', 'utf8')
  seed = seed.replaceAll("'00000000-0000-0000-0000-000000000001'", "'a0000000-0000-0000-0000-000000000001'")
  await client.query(seed)
  console.log('OK: seed_phase1.sql (tenant reciblé a000...001)')

  for (const t of ['journals','fiscal_years','analytic_plans','recurring_entries','regularization_entries','currency_revaluations','collection_reminders','distribution_grills','tvs_declarations']) {
    const r = await client.query(`SELECT count(*)::int AS n FROM ${t}`)
    console.log(`${t}: ${r.rows[0].n}`)
  }
} catch (e) {
  console.error('ERREUR:', e.message)
  process.exitCode = 1
} finally {
  await client.end()
}
