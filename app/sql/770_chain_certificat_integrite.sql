-- ═══════════════════════════════════════════════════════════════════════════
-- 770 — P1 : L'ATTESTATION D'INTÉGRITÉ TECHNIQUE (lot A3.4, proposition P1)
-- Numéro pris le 2026-10-11T08:34:03.973Z par migration-numero.mjs (ligne « plan6 A3 (certificat d'integrite, A3.4) », branche plan6/a3-moteur).
-- ═══════════════════════════════════════════════════════════════════════════
--
-- **Objet.** La proposition P1 : *« au 30/09 à 14 h 02, sur cette société, ces
-- invariants tenaient, ces chaînes ont été éprouvées, empreinte … »*. Elle
-- **monétise** tout ce que L3/L4 ont produit : les 20 invariants (413 → 456) et
-- le banc d'épreuves (433 → 436). Elle est **débloquée** par les décisions du
-- §6 bis (05/10) — le mot, la mention, qui signe — et par le dossier de
-- l'expert-comptable.
--
-- **LE CONTRAT.** `chain_certificat_integrite(p_tenant)` rend un **jsonb de
-- faits** (le vocabulaire est à l'écran, pour l'i18n) :
--   * `emis_le`, `version_migrations`, `nb_migrations` — *quelle* base atteste ;
--   * `invariants` : `{tenu, rompu, non_mesure, total}` — le **dernier** relevé
--     par invariant ; un code sans relevé est **`non_mesure`**, jamais `tenu` ;
--   * `ecarts` : la **liste** des invariants rompus, nommés — c'est le
--     différenciateur (publier ses écarts) ;
--   * `banc` : `{tenues, rompues, non_jouees, total}` — le dernier verdict par
--     `(maillon, épreuve)` ; `non_joue` VISIBLE ; + le dénominateur
--     (`maillons` × 8) pour ne pas lire « 0 verdict » comme « rien à prouver » ;
--   * `nf525` : le rapport de `verify_nf525_chain()` (déjà `jsonb`) + un drapeau
--     **`sans_objet`** quand la chaîne est **vide** — « une absence de preuve
--     n'est pas une preuve » (Q4) ; on n'écrit JAMAIS « 0 événement ».
--
-- **CE QU'ELLE NE FAIT PAS.** Elle **n'écrit rien**, **ne recalcule aucun
-- solde** (elle lit des relevés publiés), et **n'invente aucun `tenu`**. Aucune
-- prose n'y figure : ni « attestation », ni la mention légale — elles vivent à
-- l'écran (i18n), pour qu'un traducteur puisse les corriger.
--
-- **LA GARDE DE SOCIÉTÉ.** On n'atteste que **sa** société : `p_tenant` absent
-- ou égal à `current_tenant_id()`, sinon **refus** — un certificat ne traverse
-- pas la RLS d'un autre.
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.chain_certificat_integrite(p_tenant uuid DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE
  v_courant   uuid := current_tenant_id();
  v_tid       uuid;
  v_inv       jsonb;
  v_ecarts    jsonb := '[]'::jsonb;
  v_banc      jsonb;
  v_nf        jsonb;
  v_version   text;
  v_nb_migr   int := 0;
  v_maillons  int := 0;
BEGIN
  -- On n'atteste que sa propre société (même doctrine que la porte de société).
  IF p_tenant IS NOT NULL AND p_tenant IS DISTINCT FROM v_courant THEN
    RAISE EXCEPTION 'Certificat : on n''atteste que sa propre société' USING ERRCODE = '42501';
  END IF;
  v_tid := COALESCE(p_tenant, v_courant);
  IF v_tid IS NULL THEN
    RAISE EXCEPTION 'Certificat : aucune société active' USING ERRCODE = '42501';
  END IF;

  -- ── 1. LES INVARIANTS — le DERNIER relevé par code. ─────────────────────
  -- Un code du catalogue SANS aucun relevé vaut `non_mesure` : on ne publie
  -- jamais `tenu` sur ce qui n'a pas été mesuré.
  WITH dernier AS (
    SELECT DISTINCT ON (r.code)
           r.code, r.verdict, r.ecart, r.lignes_en_ecart, r.mesure_le
      FROM chain_invariant_results r
     WHERE r.tenant_id = v_tid
     ORDER BY r.code, r.mesure_le DESC, r.id DESC
  ),
  etat AS (
    SELECT i.code,
           i.libelle,
           COALESCE(d.verdict, 'non_mesure')      AS verdict,
           d.ecart,
           COALESCE(d.lignes_en_ecart, 0)         AS lignes_en_ecart,
           d.mesure_le
      FROM chain_invariants i
      LEFT JOIN dernier d ON d.code = i.code
     WHERE i.actif = true
       AND (i.tenant_id IS NULL OR i.tenant_id = v_tid)
  )
  SELECT jsonb_build_object(
           'tenu',       count(*) FILTER (WHERE verdict = 'tenu'),
           'rompu',      count(*) FILTER (WHERE verdict = 'rompu'),
           'non_mesure', count(*) FILTER (WHERE verdict = 'non_mesure'),
           'total',      count(*)
         ),
         COALESCE(jsonb_agg(jsonb_build_object(
           'code', code, 'libelle', libelle, 'ecart', ecart,
           'lignes_en_ecart', lignes_en_ecart, 'mesure_le', mesure_le
         ) ORDER BY code) FILTER (WHERE verdict = 'rompu'), '[]'::jsonb)
    INTO v_inv, v_ecarts
    FROM etat;

-- (suite : §2 le banc d'épreuves, §3 l'empreinte NF-525, §4 l'assemblage)

  -- ── 2. LE BANC D'ÉPREUVES — le DERNIER verdict par (maillon, épreuve). ───
  -- `non_joue` est COMPTÉ et VISIBLE : une épreuve jamais jouée n'est pas un
  -- succès. Le dénominateur (maillons actifs × 8) est publié À PART, pour qu'un
  -- « 0 » se lise « le banc n'a pas tourné », pas « rien à prouver ».
  WITH dernier AS (
    SELECT DISTINCT ON (r.code, r.epreuve) r.code, r.epreuve, r.verdict
      FROM chain_banc_resultats r
     WHERE r.tenant_id = v_tid
     ORDER BY r.code, r.epreuve, r.joue_le DESC, r.id DESC
  )
  SELECT jsonb_build_object(
           'tenues',     count(*) FILTER (WHERE verdict = 'tenu'),
           'rompues',    count(*) FILTER (WHERE verdict = 'rompu'),
           'non_jouees', count(*) FILTER (WHERE verdict = 'non_joue'),
           'total',      count(*)
         )
    INTO v_banc
    FROM dernier;

  SELECT count(*) INTO v_maillons FROM chain_banc_maillons WHERE actif = true;
  v_banc := COALESCE(v_banc, jsonb_build_object('tenues', 0, 'rompues', 0, 'non_jouees', 0, 'total', 0))
            || jsonb_build_object('maillons', v_maillons, 'epreuves_par_maillon', 8);

  -- ── 3. L'EMPREINTE NF-525 — un MÉCANISME, jamais une « conformité ». ─────
  -- `verify_nf525_chain()` rend déjà un `jsonb` (chaîne de hachage de la caisse).
  -- On l'embarque TEL QUEL, et l'on ajoute UN drapeau : `sans_objet` quand la
  -- chaîne est VIDE — « une absence de preuve n'est pas une preuve » (Q4). On
  -- n'écrit jamais « 0 événement » à la place de « sans objet ».
  v_nf := verify_nf525_chain();
  v_nf := v_nf || jsonb_build_object(
    'sans_objet', COALESCE((v_nf ->> 'total_events')::int, 0) = 0
  );

  -- ── 4. QUELLE BASE ATTESTE — sans version, le certificat ne se re-vérifie pas.
  SELECT COALESCE(max(id), 0) INTO v_nb_migr FROM sql_migrations_tracker;
  SELECT filename INTO v_version
    FROM sql_migrations_tracker
   ORDER BY id DESC
   LIMIT 1;

  RETURN jsonb_build_object(
    'emis_le',            now(),
    'version_migrations', v_version,
    'nb_migrations',      v_nb_migr,
    'invariants',         v_inv,
    'ecarts',             v_ecarts,
    'banc',               v_banc,
    'nf525',              v_nf
  );
END $fn$;

COMMENT ON FUNCTION public.chain_certificat_integrite(uuid) IS
  '770 (P1) : l''attestation d''intégrité TECHNIQUE, en FAITS — le dernier relevé des invariants, la liste des écarts, le rapport du banc (non_joue compris) et l''empreinte NF-525 (verify_nf525_chain). Aucune écriture, aucun recalcul, aucun « tenu » inventé ; le vocabulaire (« attestation », la mention légale) est à l''écran. On n''atteste que sa propre société.';

REVOKE ALL ON FUNCTION public.chain_certificat_integrite(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.chain_certificat_integrite(uuid) TO authenticated, service_role;

