-- 758 — chain_l16_lettrage_groupes
-- Numéro pris le 2026-10-11T06:36:56.352Z par migration-numero.mjs (ligne « plan6 A3 L16 (familles restantes) », branche plan6/a3-moteur).
-- ═══════════════════════════════════════════════════════════════════════════
-- 758 — L16 · le chaînage interne de la COMPTABILITÉ : le GROUPE DE LETTRAGE et
--       ses LIGNES DE JOURNAL
-- ═══════════════════════════════════════════════════════════════════════════
-- Le référentiel (§B.3) ouvre la famille Comptabilité sur « lettrage ↔ âge de la
-- dette ↔ relance ↔ provision pour dépréciation ↔ écriture de clôture ». C'est
-- aussi la **demande R3 d'A1 restée ouverte** (voir `PARTIE-A1.md`) : « Bâtir le
-- lien `lettrage_groups` ↔ `journal_lines` » — rend `INV-07` possible.
--
-- CE QUE LA MESURE A TROUVÉ AVANT D'ÉCRIRE (base neuve, 333 migrations) :
--   * `lettrage_groups` EXISTE (124, puis 187) et `journal_lines.lettrage_group_id`
--     EXISTE — mais **AUCUN lien de chaîne** (`document_links`) n'est posé, et
--     `lettrage_groups` **n'est pas au registre** : un lettrage est **invisible
--     pour la frise** ;
--   * aucun contrat d'effet, donc aucun maillon.
--
-- CE QUE CE FICHIER POSE : le type `lettrage_groups` au registre, le contrat
-- d'effet `rev.line.lettered`, et le maillon `chain_l16_lettrage_group` — il TRACE
-- CHAQUE ligne de journal du groupe vers ce groupe (`link_documents`, type
-- `created_from`), idempotent par CONSTRUCTION (l'index unique partiel de
-- `link_documents` : rejouer ne double aucun lien).
--
-- ⚠️ IDEMPOTENCE STRUCTURELLE, PAS UN `IF`. Il y a N liens (un par ligne) : refuser
-- un « rejeu » n'aurait pas de sens, le maillon REND le nombre de lignes tracées et
-- rejouer rend le même nombre sans rien ajouter (doctrine du pont de la `415`).
--
-- ⚠️ LA COHÉRENCE EST VÉRIFIÉE : un groupe ANNULÉ est refusé ; un groupe SANS
-- LIGNE ne trace rien et le dit (il ne fabrique pas un lien vers rien).
-- ═══════════════════════════════════════════════════════════════════════════

-- ── 1. Le registre accueille le GROUPE DE LETTRAGE ─────────────────────────
INSERT INTO public.chain_document_types (code, table_name, ligne_table, libelle_fr) VALUES
  ('lettrage_groups', 'lettrage_groups', NULL, 'Groupe de lettrage')
ON CONFLICT (code) DO UPDATE SET
  table_name  = EXCLUDED.table_name,
  ligne_table = EXCLUDED.ligne_table,
  libelle_fr  = EXCLUDED.libelle_fr;

-- ── 2. Le CONTRAT d'effet (L7) : sans lui, la porte G2 refuse le maillon ───
INSERT INTO public.document_effects
  (tenant_id, document_type, evenement, effet, ecrit_comptable, journal_code,
   touche_stock, touche_paie, reversible, obligatoire, actif, note)
SELECT NULL, 'journal_lines', 'lettered', 'rev.line.lettered', false, NULL,
       false, false, true, false, true,
       'L16/758 : une ligne de journal est lettrée — rattachée à son groupe de lettrage — et le lien amont→aval est posé. Aucune écriture nouvelle ici (le lettrage rapproche, il ne comptabilise pas). Réversible : fermer les liens.'
WHERE NOT EXISTS (
  SELECT 1 FROM public.document_effects
  WHERE document_type = 'journal_lines' AND evenement = 'lettered' AND effet = 'rev.line.lettered'
);

-- ── 3. Le MAILLON : `chain_l16_lettrage_group` ─────────────────────────────
CREATE OR REPLACE FUNCTION public.chain_l16_lettrage_group(p_group_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE
  v_g  lettrage_groups%ROWTYPE;
  v_l  record;
  v_n  integer := 0;
BEGIN
  -- 1. Le groupe, borné à la société.
  SELECT * INTO v_g FROM lettrage_groups
   WHERE id = p_group_id AND tenant_id = current_tenant_id();
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Groupe de lettrage introuvable (ou hors de votre société)' USING ERRCODE = 'no_data_found';
  END IF;

  -- 2. Un groupe annulé ne se trace pas.
  IF v_g.status = 'cancelled' THEN
    RAISE EXCEPTION 'Groupe de lettrage % annulé : rien à tracer', v_g.lettrage_code
      USING ERRCODE = 'check_violation';
  END IF;

  -- 3. Chaque ligne de journal portée par le groupe est tracée. La direction est
  --    LIGNE → GROUPE : `link_documents` fusionne deux liens de MÊME amont, effet
  --    et ligne-amont (« met à jour son aval au lieu d'empiler », leçon de la 401)
  --    — avec le groupe pour amont, N lignes ne tiendraient qu'UN lien. Chaque
  --    ligne a donc son propre lien, et l'idempotence reste STRUCTURELLE.
  FOR v_l IN
    SELECT id FROM journal_lines
     WHERE tenant_id = v_g.tenant_id AND lettrage_group_id = p_group_id
     ORDER BY id
  LOOP
    PERFORM link_documents(
      v_g.tenant_id, 'journal_lines', v_l.id, 'lettrage_groups', p_group_id,
      'rev.line.lettered', 'created_from');
    v_n := v_n + 1;
  END LOOP;

  -- 4. Un groupe sans ligne ne fabrique pas un lien vers rien : c'est DIT.
  IF v_n = 0 THEN
    RAISE EXCEPTION 'Groupe de lettrage % sans ligne : rien à tracer', v_g.lettrage_code
      USING ERRCODE = 'check_violation';
  END IF;

  RETURN jsonb_build_object(
    'success', true, 'group_id', p_group_id, 'code', v_g.lettrage_code, 'lines', v_n);
END $fn$;

COMMENT ON FUNCTION public.chain_l16_lettrage_group(uuid) IS
  'L16/758 : chaîne comptable ligne de journal → son groupe de lettrage. Idempotent par construction (index unique partiel de link_documents), refuse un groupe annulé ou sans ligne, tracé (link_documents, effet rev.line.lettered). SECURITY DEFINER, borné à current_tenant_id().';

-- ── 4. Droits : jamais PUBLIC — la règle de la garde 228 T06 ───────────────
REVOKE ALL ON FUNCTION public.chain_l16_lettrage_group(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.chain_l16_lettrage_group(uuid) TO authenticated;
