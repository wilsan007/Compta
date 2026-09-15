// TEST-01: Test d'intégration base de données
// Vérifie que les RPC critiques et les invariants comptables existent
// dans le schéma de production.
//
// Ce test nécessite DATABASE_URL pour se connecter à la base.
// En CI, il s'exécute contre un Postgres vierge avec les migrations appliquées.
// Localement, il peut s'exécuter contre la base de développement.

import { describe, it, expect, beforeAll, afterAll } from 'vitest'

// Skip si pas de DATABASE_URL (tests unitaires normaux)
const DB_URL = process.env.DATABASE_URL
const it_db = DB_URL ? it : it.skip

let pgClient: any = null

beforeAll(async () => {
  if (!DB_URL) return
  const pg = await import('pg')
  pgClient = new pg.Client({ connectionString: DB_URL, ssl: { rejectUnauthorized: false } })
  await pgClient.connect()
})

afterAll(async () => {
  if (pgClient) await pgClient.end()
})

describe('DB Integration — RPC critiques (TEST-01)', () => {
  it_db('current_tenant_id() existe et lit x-tenant-id', async () => {
    const res = await pgClient.query(
      "SELECT prosrc FROM pg_proc WHERE proname = 'current_tenant_id'"
    )
    expect(res.rows.length).toBeGreaterThan(0)
    expect(res.rows[0].prosrc).toContain('request.headers')
    expect(res.rows[0].prosrc).toContain('x-tenant-id')
  })

  it_db('post_journal_entry() RPC existe (ACC-01)', async () => {
    const res = await pgClient.query(
      "SELECT 1 FROM pg_proc WHERE proname = 'post_journal_entry'"
    )
    expect(res.rows.length).toBeGreaterThan(0)
  })

  it_db('increment_stock() RPC existe (APP-01)', async () => {
    const res = await pgClient.query(
      "SELECT 1 FROM pg_proc WHERE proname = 'increment_stock'"
    )
    expect(res.rows.length).toBeGreaterThan(0)
  })

  it_db('decrement_stock() RPC existe (APP-01)', async () => {
    const res = await pgClient.query(
      "SELECT 1 FROM pg_proc WHERE proname = 'decrement_stock'"
    )
    expect(res.rows.length).toBeGreaterThan(0)
  })

  it_db('generate_recurring_entry() RPC existe (APP-01)', async () => {
    const res = await pgClient.query(
      "SELECT 1 FROM pg_proc WHERE proname = 'generate_recurring_entry'"
    )
    expect(res.rows.length).toBeGreaterThan(0)
  })

  it_db('create_tenant_for_current_user() RPC existe (DB-01)', async () => {
    const res = await pgClient.query(
      "SELECT 1 FROM pg_proc WHERE proname = 'create_tenant_for_current_user'"
    )
    expect(res.rows.length).toBeGreaterThan(0)
  })

  it_db('get_next_piece_number() RPC existe (ACC-01)', async () => {
    const res = await pgClient.query(
      "SELECT 1 FROM pg_proc WHERE proname = 'get_next_piece_number'"
    )
    expect(res.rows.length).toBeGreaterThan(0)
  })

  it_db('aucune policy USING(true) restante (SEC-02)', async () => {
    const res = await pgClient.query(
      "SELECT tablename, policyname FROM pg_policies WHERE schemaname = 'public' AND (qual = 'true' OR with_check = 'true' OR qual = '(true)' OR with_check = '(true)')"
    )
    expect(res.rows.length).toBe(0)
  })

  it_db('trigger prevent_posted_entry_modification existe (ACC-01)', async () => {
    const res = await pgClient.query(
      "SELECT 1 FROM pg_trigger WHERE tgname = 'prevent_posted_entry_modification'"
    )
    expect(res.rows.length).toBeGreaterThan(0)
  })

  it_db('trigger check_journal_entry_balance existe (ACC-01)', async () => {
    const res = await pgClient.query(
      "SELECT 1 FROM pg_trigger WHERE tgname = 'check_journal_entry_balance'"
    )
    expect(res.rows.length).toBeGreaterThan(0)
  })

  it_db('vue balance_sheet existe (ACC-02)', async () => {
    const res = await pgClient.query(
      "SELECT 1 FROM pg_views WHERE schemaname = 'public' AND viewname = 'balance_sheet'"
    )
    expect(res.rows.length).toBeGreaterThan(0)
  })

  it_db('vue trial_balance existe (ACC-02)', async () => {
    const res = await pgClient.query(
      "SELECT 1 FROM pg_views WHERE schemaname = 'public' AND viewname = 'trial_balance'"
    )
    expect(res.rows.length).toBeGreaterThan(0)
  })

  it_db('vue rls_audit existe (SEC-02)', async () => {
    const res = await pgClient.query(
      "SELECT 1 FROM pg_views WHERE schemaname = 'public' AND viewname = 'rls_audit'"
    )
    expect(res.rows.length).toBeGreaterThan(0)
  })
})
