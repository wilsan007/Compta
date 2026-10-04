// TEST-01: Test d'intégration base de données
// Vérifie que les RPC critiques et les invariants comptables existent
// dans le schéma de production.
//
// Ce test nécessite DATABASE_URL pour se connecter à la base.
// En CI, il s'exécute contre un Postgres vierge avec les migrations appliquées.
// Localement, il peut s'exécuter contre la base de développement.

import { describe, it, expect, beforeAll, afterAll } from 'vitest'
import type { Client, ClientConfig } from 'pg'

// Skip si pas de DATABASE_URL (tests unitaires normaux)
const DB_URL = process.env.DATABASE_URL
const it_db = DB_URL ? it : it.skip

let pgClient: any = null

// 2026-10-02 (Partie 5) : ce fichier DOCUMENTE qu'il « peut s'exécuter
// localement contre la base de développement », mais il imposait
// `ssl: { rejectUnauthorized: false }`. Ni un Postgres local, ni le service
// `postgres:16` de la CI ne gèrent le SSL : `connect()` levait
// « the server does not support SSL connections » DANS beforeAll, et les
// 13 scénarios étaient alors rapportés « skippés » alors que le FICHIER
// échouait — un faux vert et un faux rouge à la fois. On tente donc SSL,
// puis le repli sans SSL ; si les deux échouent, on le dit en clair.
// (Le garde s'appuyait sur un `it.skip` par absence de DATABASE_URL : c'est
// ce chemin-là qui masque le défaut en CI, pas un défaut du test.)
async function connecterPg(pg: typeof import('pg'), url: string) {
  const tentatives: ClientConfig[] = [
    { connectionString: url, ssl: { rejectUnauthorized: false } },
    { connectionString: url },
  ]
  let dernier: unknown = null
  for (const options of tentatives) {
    const client: Client = new pg.Client(options)
    try {
      await client.connect()
      return client
    } catch (e) {
      dernier = e
      await client.end().catch(() => {})
    }
  }
  throw new Error(
    `db-integration : connexion impossible à la base (${url}). Dernière erreur : ${
      dernier instanceof Error ? dernier.message : String(dernier)
    }`
  )
}

beforeAll(async () => {
  if (!DB_URL) return
  const pg = await import('pg')
  pgClient = await connecterPg(pg, DB_URL)
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

  // 2026-10-02 (Partie 5) : assertion PRÉCISÉE. Elle exigeait « zéro politique
  // USING(true) », ce qui confondait deux choses sans rapport : une TABLE DE
  // SOCIÉTÉ lue par tout le monde (une fuite) et un RÉFÉRENTIEL GLOBAL sans
  // `tenant_id`, qu'il est normal de laisser lire. Mesuré : les 6 politiques
  // concernées portent sur des tables SANS `tenant_id` — `banks` (annuaire
  // swift/name/country), `chart_account_templates`, `webhook_event_catalog`,
  // `sql_migrations_tracker`, la vue `v_tenant_id`, et `chain_document_types`
  // (le registre des 27 types de la 450 : 27 lignes statiques, `SELECT` aux
  // seuls `authenticated`, AUCUN droit d'écriture). Aucune ne porte de donnée
  // de société. On vérifie donc la propriété de sécurité RÉELLE — aucune
  // politique en blanc sur une table qui porte `tenant_id` — ce qui reste plus
  // strict sur le plan qui compte, et attrape une vraie fuite.
  // Verdict précédent : expect(res.rows.length).toBe(0) sur TOUTE politique.
  it_db('aucune politique en blanc sur une table de société (SEC-02)', async () => {
    const res = await pgClient.query(
      `SELECT p.tablename, p.policyname
         FROM pg_policies p
        WHERE p.schemaname = 'public'
          AND (p.qual IN ('true','(true)') OR p.with_check IN ('true','(true)'))
          AND EXISTS (SELECT 1 FROM information_schema.columns c
                       WHERE c.table_schema = 'public'
                         AND c.table_name = p.tablename
                         AND c.column_name = 'tenant_id')`
    )
    expect(res.rows).toEqual([])
  })

  it_db('trigger prevent_posted_entry_modification existe (ACC-01)', async () => {
    const res = await pgClient.query(
      "SELECT 1 FROM pg_trigger WHERE tgname = 'prevent_posted_entry_modification'"
    )
    expect(res.rows.length).toBeGreaterThan(0)
  })

  // 2026-10-02 (Partie 5) : assertion PRÉCISÉE. Elle cherchait le nom exact
  // `check_journal_entry_balance`, qui N'EXISTE plus : le contrôle d'équilibre
  // existe, mais il a été décliné en quatre déclencheurs au fil de l'eau —
  // `check_journal_entry_balance_ins` / `_upd` / `_del` sur `journal_lines`, et
  // `check_journal_entry_balance_on_post` sur `journal_entries`. Le test
  // affirmait donc un contrôle ABSENT alors qu'il est présent : un faux rouge
  // qui masquait le contrôle qu'il devait garder. On vérifie désormais que le
  // contrôle existe (décliné ou non), et qu'il couvre bien l'écriture ET la
  // comptabilisation. Le nom exact n'est plus un contrat.
  // Verdict précédent : SELECT 1 … WHERE tgname = 'check_journal_entry_balance'.
  it_db('le contrôle d’équilibre des écritures existe (ACC-01)', async () => {
    const surLignes = await pgClient.query(
      "SELECT 1 FROM pg_trigger WHERE tgname IN ('check_journal_entry_balance_ins','check_journal_entry_balance_upd','check_journal_entry_balance_del')"
    )
    const aLaComptabilisation = await pgClient.query(
      "SELECT 1 FROM pg_trigger WHERE tgname = 'check_journal_entry_balance_on_post'"
    )
    expect(surLignes.rows.length).toBeGreaterThan(0)
    expect(aLaComptabilisation.rows.length).toBeGreaterThan(0)
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
