-- Numéro pris le 2026-10-11T09:41:51.571Z par migration-numero.mjs (ligne « plan6 A3 L16 (familles restantes) », branche plan6/a3-moteur).

-- ═══════════════════════════════════════════════════════════════════════════
-- 763 — L16 · le chaînage interne de la COMPTABILITÉ : l'EXERCICE et son
--       ÉCRITURE D'À-NOUVEAUX (son ouverture)
-- ═══════════════════════════════════════════════════════════════════════════
-- Le référentiel (§B.3) : « lettrage ↔ âge de la dette ↔ relance ↔ provision ↔
-- écriture de clôture ». Le lot `760` a fait la clôture ; voici **l'ouverture**,
-- qui en était la suite naturelle — et la provision s'est retirée d'elle-même
-- (voir PARTIE-A3.md : `calculate_provisions` rend un jsonb, aucun objet
-- « provision » n'existe).
--
-- CE QUE LA MESURE A TROUVÉ AVANT D'ÉCRIRE (base neuve) :
--   * l'écrivain existe : `close_fiscal_year` (`107`, réécrit par `153`) pose
--     l'écriture d'à-nouveaux avec **`journal_code = 'AN'`**,
--     **`date = <premier jour de l'exercice OUVERT>`**,
--     `number = 'AN-<année>-<séquence>'`, `reference = 'AN-<code de l''exercice
--     CLOS>'` et `description = 'À-nouveaux <code de l''exercice ouvert>'`. Le
--     `reference` nomme l'exercice **fermé** : il ne sert donc PAS à identifier
--     l'exercice ouvert — `date` et `journal_code` le font, et c'est mesuré ;
--   * `187` (le noyau comptable strict) a ajouté **`journal_entries.fiscal_year_id`**
--     (FK vers `fiscal_years`) — et son garde `journal_entry_guard` la **POSE** :
--     `NEW.fiscal_year_id := v_fy.id`, l'exercice trouvé par contenance de date, à
--     l'insertion COMME à la modification. **La colonne n'est donc pas vide** ;
--     une première version de ce fichier comptait l'écrire — la mesure l'a
--     démentie, et c'est tant mieux ;
--   * **une écriture VALIDÉE est IMMUABLE** : `prevent_posted_entry_modification`
--     refuse tout `UPDATE` d'une écriture au statut `posted` (« utiliser
--     l'extourne »). **MESURÉ pendant la construction de cette suite** : la
--     tentative d'écriture d'une colonne sur l'écriture d'à-nouveaux a été refusée
--     net, et le maillon aurait échoué en production. C'est cette mesure qui a
--     RETIRÉ du maillon l'écriture qu'il prévoyait ;
--   * le vrai manque reste donc entier : **aucun lien de chaîne** — la frise
--     ignore l'ouverture, et rien ne dit quelle écriture ouvre quel exercice
--     hors d'une contenance de date recalculée à chaque fois ;
--   * aucun contrat d'effet, donc aucun maillon.
--
-- CE QUE CE FICHIER POSE : le contrat d'effet `rev.fiscal_year.opening_entry` et
-- le maillon `chain_l16_fiscal_year_opening` — idempotent (rejeu REFUSÉ),
-- réversible, tracé (`link_documents`).
--
-- ⚠️ LA COHÉRENCE EST VÉRIFIÉE, PAS SUPPOSÉE : une écriture qui n'est pas du
-- journal `AN` est refusée ; une écriture qui **n'est pas datée du premier jour**
-- de l'exercice est refusée (elle n'ouvre pas cet exercice). Chaque refus dit sa
-- raison. (L'appartenance de l'écriture à SON exercice n'est PAS revérifiée ici :
-- `187` la tient par contenance de date — la revérifier ferait doublon avec le
-- garde, et un refus qu'on ne peut pas provoquer n'est pas un refus, c'est du code
-- mort.)
--
-- ⚠️ CE MAILLON N'ÉCRIT **RIEN** — et c'est une décision MESURÉE, pas une timidité :
-- le garde de l'écriture (`187`) pose déjà l'exercice, et une écriture validée est
-- immuable. Il VÉRIFIE et il TRACE. Une première version écrivait la colonne : la
-- mesure l'a défaite avant la publication (voir le § 187 ci-dessus).
-- ═══════════════════════════════════════════════════════════════════════════

-- ── 1. Le registre : EXIGÉ, pas supposé ────────────────────────────────────
-- (`760` a fait entrer `fiscal_years` ; `journal_entries` y est depuis L1.) Si l'un
-- des deux manquait, `link_documents` refuserait le lien (451) — autant le dire au
-- déploiement.
DO $$
BEGIN
  IF (SELECT count(*) FROM public.chain_document_types
       WHERE code IN ('fiscal_years', 'journal_entries')) <> 2 THEN
    RAISE EXCEPTION '763 : le registre n''accueille pas fiscal_years ET journal_entries — le lien serait refusé (451)'
      USING ERRCODE = 'check_violation';
  END IF;
END $$;

-- ── 2. Le CONTRAT d'effet (L7) : sans lui, la porte G2 refuse le maillon ───
INSERT INTO public.document_effects
  (tenant_id, document_type, evenement, effet, ecrit_comptable, journal_code,
   touche_stock, touche_paie, reversible, obligatoire, actif, note)
SELECT NULL, 'fiscal_years', 'opened', 'rev.fiscal_year.opening_entry', true, 'AN',
       false, false, true, false, true,
       'L16/763 : un exercice s''ouvre par son écriture d''à-nouveaux (journal AN, datée de son premier jour), et le lien amont→aval est posé. Écrit par close_fiscal_year (153). Réversible : rompre le lien.'
WHERE NOT EXISTS (
  SELECT 1 FROM public.document_effects
  WHERE document_type = 'fiscal_years' AND evenement = 'opened'
    AND effet = 'rev.fiscal_year.opening_entry'
);

-- ── 3. Le MAILLON : `chain_l16_fiscal_year_opening` ────────────────────────
CREATE OR REPLACE FUNCTION public.chain_l16_fiscal_year_opening(p_fy_id uuid, p_entry_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE
  v_f     fiscal_years%ROWTYPE;
  v_e     journal_entries%ROWTYPE;
  v_exist uuid;
BEGIN
  -- 1. L'exercice, borné à la société.
  SELECT * INTO v_f FROM fiscal_years
   WHERE id = p_fy_id AND tenant_id = current_tenant_id();
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Exercice introuvable (ou hors de votre société)' USING ERRCODE = 'no_data_found';
  END IF;

  -- 2. L'écriture, bornée à la société.
  SELECT * INTO v_e FROM journal_entries
   WHERE id = p_entry_id AND tenant_id = current_tenant_id();
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Écriture introuvable (ou hors de votre société)' USING ERRCODE = 'no_data_found';
  END IF;

  -- 3. LES REFUS EXPLICITES : chaque refus porte sa raison.
  IF v_e.journal_code <> 'AN' THEN
    RAISE EXCEPTION 'L''écriture % n''est pas du journal des à-nouveaux (AN) : elle n''ouvre pas un exercice', v_e.number
      USING ERRCODE = 'check_violation';
  END IF;
  IF v_e.date <> v_f.start_date THEN
    RAISE EXCEPTION 'L''écriture % est datée du % : elle n''ouvre pas l''exercice % (qui s''ouvre le %)',
      v_e.number, v_e.date, v_f.code, v_f.start_date
      USING ERRCODE = 'check_violation';
  END IF;
  -- 4. IDEMPOTENCE : le LIEN actif fait foi pour la frise.
  SELECT l.id INTO v_exist FROM document_links l
   WHERE l.tenant_id  = v_f.tenant_id
     AND l.amont_type = 'fiscal_years'    AND l.amont_id = p_fy_id
     AND l.aval_type  = 'journal_entries' AND l.aval_id  = p_entry_id
     AND l.effet = 'rev.fiscal_year.opening_entry' AND l.etat = 'actif'
   LIMIT 1;
  IF v_exist IS NOT NULL THEN
    RAISE EXCEPTION 'L''exercice % est déjà ouvert par l''écriture %', v_f.code, v_e.number
      USING ERRCODE = 'unique_violation';
  END IF;

  -- 5. LE LIEN : c'est lui qui rend la chaîne VISIBLE (I-01). Rien n'est écrit
  --    d'autre : le garde de l'écriture (187) a déjà posé l'exercice, et une
  --    écriture validée est IMMUABLE (mesuré — voir l'en-tête du fichier).
  PERFORM link_documents(
    v_f.tenant_id, 'fiscal_years', p_fy_id, 'journal_entries', p_entry_id,
    'rev.fiscal_year.opening_entry', 'generated_entry');

  RETURN jsonb_build_object(
    'success', true, 'fiscal_year_id', p_fy_id, 'code', v_f.code,
    'entry_id', p_entry_id, 'entry_number', v_e.number);
END $fn$;

COMMENT ON FUNCTION public.chain_l16_fiscal_year_opening(uuid, uuid) IS
  'L16/763 : chaîne comptable exercice → son écriture d''à-nouveaux (son ouverture). Idempotent (rejeu refusé), refuse une écriture d''un autre journal que AN et une écriture non datée du premier jour de l''exercice, tracé (link_documents, effet rev.fiscal_year.opening_entry). N''ÉCRIT RIEN — mesure : le garde de l''écriture (187) pose déjà fiscal_year_id, et une écriture validée est immuable. SECURITY DEFINER, borné à current_tenant_id().';

-- ── 4. Droits : jamais PUBLIC — la règle de la garde 228 T06 ───────────────
REVOKE ALL ON FUNCTION public.chain_l16_fiscal_year_opening(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.chain_l16_fiscal_year_opening(uuid, uuid) TO authenticated;

