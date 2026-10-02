"""Partie 5, tâche 5.9 — fabrique la migration 455 à partir du corps COURANT de chain_invariant_mesurer.

Usage :
  psql "$DATABASE_URL" -Atc "select pg_get_functiondef('chain_invariant_mesurer'::regproc)" > /tmp/mesurer.sql
  python3 gen455.py /tmp/mesurer.sql app/sql/455_chain_inv19_mesurable.sql

Le corps est relevé sur une base NEUVE à jour (toutes les migrations du dépôt) : la 455 le
reproduit à l'identique et n'y ajoute QUE la branche INV-19 et trois variables.
"""
import sys
src = open(sys.argv[1]).read().rstrip()
lines = src.split('\n')

i = next(k for k, l in enumerate(lines) if l.strip().startswith('v_n3 integer'))
lines.insert(i + 1, '  v_t   record;          -- 455 : INV-19, un type du registre')
lines.insert(i + 2, "  v_ids uuid[] := '{}';  -- 455 : INV-19, les liens orphelins (sans doublon)")
lines.insert(i + 3, '  v_lot uuid[];          -- 455 : INV-19, le lot rendu par une requête dynamique')

j = next(k for k, l in enumerate(lines) if 'Un code inscrit' in l and 'sans branche' in l)

branch = r"""  -- ── INV-19 (455, Partie 5) — aucun lien ACTIF ne pointe vers un document,
  --    ou une ligne amont, qui n'existe plus dans la société. Le type se résout
  --    par le registre 450 ; un lien dont le type n'y est pas (base ancienne,
  --    contrainte NOT VALID) compte aussi comme orphelin. Chaque lien est
  --    compté UNE fois, même si l'amont et l'aval ont disparu tous les deux.
  ELSIF p_code = 'INV-19' THEN
    SELECT count(*) INTO v_n2
    FROM document_links WHERE tenant_id = p_tenant AND etat = 'actif';

    FOR v_t IN SELECT code, table_name, ligne_table FROM chain_document_types LOOP
      EXECUTE format(
        'SELECT array_agg(l.id) FROM document_links l
          WHERE l.tenant_id = $1 AND l.etat = ''actif'' AND l.amont_type = $2
            AND NOT EXISTS (SELECT 1 FROM public.%I d WHERE d.id = l.amont_id AND d.tenant_id = $1)',
        v_t.table_name) INTO v_lot USING p_tenant, v_t.code;
      v_ids := v_ids || COALESCE(v_lot, '{}');

      EXECUTE format(
        'SELECT array_agg(l.id) FROM document_links l
          WHERE l.tenant_id = $1 AND l.etat = ''actif'' AND l.aval_type = $2
            AND NOT EXISTS (SELECT 1 FROM public.%I d WHERE d.id = l.aval_id AND d.tenant_id = $1)',
        v_t.table_name) INTO v_lot USING p_tenant, v_t.code;
      v_ids := v_ids || COALESCE(v_lot, '{}');

      IF v_t.ligne_table IS NOT NULL THEN
        EXECUTE format(
          'SELECT array_agg(l.id) FROM document_links l
            WHERE l.tenant_id = $1 AND l.etat = ''actif'' AND l.amont_type = $2
              AND l.amont_ligne_id IS NOT NULL
              AND NOT EXISTS (SELECT 1 FROM public.%I d WHERE d.id = l.amont_ligne_id AND d.tenant_id = $1)',
          v_t.ligne_table) INTO v_lot USING p_tenant, v_t.code;
        v_ids := v_ids || COALESCE(v_lot, '{}');
      END IF;
    END LOOP;

    SELECT array_agg(l.id) INTO v_lot
    FROM document_links l
    WHERE l.tenant_id = p_tenant AND l.etat = 'actif'
      AND (NOT EXISTS (SELECT 1 FROM chain_document_types d WHERE d.code = l.amont_type)
        OR NOT EXISTS (SELECT 1 FROM chain_document_types d WHERE d.code = l.aval_type));
    v_ids := v_ids || COALESCE(v_lot, '{}');

    SELECT count(DISTINCT x) INTO v_n FROM unnest(v_ids) AS x;
    v_a := v_n2::numeric;
    v_b := (v_n2 - v_n)::numeric;
    lignes_en_ecart := v_n;
    detail := jsonb_build_object(
      'liens_actifs', v_n2, 'liens_orphelins', v_n,
      'exemples', (SELECT to_jsonb(array_agg(e.x))
                     FROM (SELECT DISTINCT x FROM unnest(v_ids) AS x LIMIT 5) e));
"""
lines.insert(j, branch.rstrip('\n'))
body = '\n'.join(lines).rstrip()
if not body.endswith(';'):
    body += ';'

header = """-- ═══════════════════════════════════════════════════════════════════════════
-- 455 — Partie 5 : INV-19 devient MESURABLE (« aucun document aval n'est
--       orphelin de son amont »)
-- ═══════════════════════════════════════════════════════════════════════════
--
-- La 413 avait inscrit INV-19 « non mesurable », avec une raison exacte : sans
-- registre des types, rien ne permettait de résoudre `amont_type` en table.
-- Le registre existe (450) : la raison tombe, l'invariant se mesure.
--
-- Ce fichier :
--   1. passe INV-19 à `mesurable = true` (raison effacée) ;
--   2. réécrit `chain_invariant_mesurer` À L'IDENTIQUE (corps relevé sur une
--      base neuve à jour, par pg_get_functiondef) en ajoutant UNE
--      branche, `INV-19`, juste avant la branche finale qui lève une erreur.
--
-- ⚠️ Toute migration qui réécrit à nouveau `chain_invariant_mesurer` DOIT
-- partir du corps relevé sur une base neuve qui contient la 455 — sinon elle
-- efface la branche INV-19 en silence. La suite 450 (T12) le détecte.
-- ═══════════════════════════════════════════════════════════════════════════

UPDATE public.chain_invariants
   SET mesurable = true,
       raison_non_mesurable = NULL
 WHERE code = 'INV-19' AND tenant_id IS NULL;

"""
footer = """

REVOKE ALL ON FUNCTION public.chain_invariant_mesurer(uuid, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.chain_invariant_mesurer(uuid, text) TO service_role;
"""
open(sys.argv[2], 'w').write(header + body + footer)
print('ok', len(header + body + footer))
