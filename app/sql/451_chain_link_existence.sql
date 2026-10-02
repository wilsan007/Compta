-- ═══════════════════════════════════════════════════════════════════════════
-- 451 — Partie 5 : un lien ne se pose que vers des documents qui EXISTENT
-- ═══════════════════════════════════════════════════════════════════════════
--
-- Défaut mesuré le 02/10/2026 : `link_documents` n'examinait ni l'existence de
-- l'amont, ni celle de l'aval, ni celle de la ligne amont. Un appel avec un
-- identifiant inventé créait un lien « actif » vers rien.
--
-- Ce fichier :
--   1. crée `chain_document_existe(société, type, id, ligne)` — la seule
--      fonction qui sait résoudre un type en table (registre 450) ;
--   2. réécrit `link_documents` À L'IDENTIQUE (corps de la 402) en ajoutant
--      quatre contrôles avant l'écriture : amont, ligne amont, aval, ligne aval.
--
-- Le refus porte le code 23503 (foreign_key_violation) : c'est exactement la
-- nature du défaut, et PostgREST le rend en 409.
-- Les 23 maillons qui appellent `link_documents` le font APRÈS l'écriture du
-- document (déclencheurs AFTER ou RPC) : mesuré le 02/10, aucun n'est gêné.
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.chain_document_existe(
  p_tenant uuid,
  p_type   text,
  p_id     uuid,
  p_ligne  boolean DEFAULT false
) RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $fn$
DECLARE
  v_table text;
  v_ok    boolean;
BEGIN
  SELECT CASE WHEN p_ligne THEN d.ligne_table ELSE d.table_name END
    INTO v_table
  FROM chain_document_types d
  WHERE d.code = p_type;

  IF v_table IS NULL THEN
    RETURN false;   -- type inconnu, ou type sans table de lignes
  END IF;

  EXECUTE format('SELECT EXISTS (SELECT 1 FROM public.%I WHERE id = $1 AND tenant_id = $2)', v_table)
    INTO v_ok
    USING p_id, p_tenant;
  RETURN v_ok;
END $fn$;

COMMENT ON FUNCTION public.chain_document_existe(uuid, text, uuid, boolean) IS
  '451 : vrai si le document (ou sa ligne, p_ligne = true) de ce type existe DANS CETTE SOCIÉTÉ. Résout le type par le registre chain_document_types. Interne : non exposée.';

REVOKE ALL ON FUNCTION public.chain_document_existe(uuid, text, uuid, boolean) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.link_documents(
  p_tenant      uuid,
  p_amont_type  text,
  p_amont_id    uuid,
  p_aval_type   text,
  p_aval_id     uuid,
  p_effet       text,
  p_link_type   text,
  p_payload     jsonb DEFAULT '{}'::jsonb,
  p_amont_ligne uuid DEFAULT NULL,
  p_aval_ligne  uuid DEFAULT NULL
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $fn$
DECLARE
  v_id   uuid;
  v_tour integer;
BEGIN
  IF p_tenant IS NULL THEN
    RAISE EXCEPTION 'Chaînage refusé : aucune société — un lien sans société n''existe pas (cloisonnement fermé).'
      USING ERRCODE = '23514';
  END IF;
  IF p_amont_id IS NULL OR p_aval_id IS NULL THEN
    RAISE EXCEPTION 'Chaînage refusé : le lien % → % est incomplet (identifiant amont ou aval absent).',
      p_amont_type, p_aval_type USING ERRCODE = '23514';
  END IF;
  IF COALESCE(btrim(p_effet), '') = '' THEN
    RAISE EXCEPTION 'Chaînage refusé : maillon sans nom (effet vide). Un lien sans effet n''est pas idempotent.'
      USING ERRCODE = '23514';
  END IF;

  -- 451 : les quatre contrôles d'existence (Partie 5).
  IF NOT chain_document_existe(p_tenant, p_amont_type, p_amont_id) THEN
    RAISE EXCEPTION 'Chaînage refusé : le document amont % % n''existe pas dans cette société (ou son type n''est pas inscrit au registre chain_document_types).',
      p_amont_type, p_amont_id USING ERRCODE = '23503';
  END IF;
  IF p_amont_ligne IS NOT NULL AND NOT chain_document_existe(p_tenant, p_amont_type, p_amont_ligne, true) THEN
    RAISE EXCEPTION 'Chaînage refusé : la ligne amont % du type % n''existe pas dans cette société (ou ce type ne déclare pas de table de lignes).',
      p_amont_ligne, p_amont_type USING ERRCODE = '23503';
  END IF;
  IF NOT chain_document_existe(p_tenant, p_aval_type, p_aval_id) THEN
    RAISE EXCEPTION 'Chaînage refusé : le document aval % % n''existe pas dans cette société (ou son type n''est pas inscrit au registre chain_document_types).',
      p_aval_type, p_aval_id USING ERRCODE = '23503';
  END IF;
  IF p_aval_ligne IS NOT NULL AND NOT chain_document_existe(p_tenant, p_aval_type, p_aval_ligne, true) THEN
    RAISE EXCEPTION 'Chaînage refusé : la ligne aval % du type % n''existe pas dans cette société (ou ce type ne déclare pas de table de lignes).',
      p_aval_ligne, p_aval_type USING ERRCODE = '23503';
  END IF;

  -- Le tour suivant du couple (tous états confondus : un lien fermé a fait
  -- monter le compteur). Lu sous la même clé que l'index partiel.
  SELECT COALESCE(max(dl.tour), 0) + 1 INTO v_tour
  FROM document_links dl
  WHERE dl.tenant_id = p_tenant
    AND dl.amont_type = p_amont_type
    AND dl.amont_id = p_amont_id
    AND dl.effet = p_effet
    AND dl.amont_ligne_id IS NOT DISTINCT FROM p_amont_ligne;

  INSERT INTO document_links (tenant_id, amont_type, amont_id, amont_ligne_id,
                              aval_type, aval_id, aval_ligne_id,
                              link_type, effet, payload, created_by, tour)
  VALUES (p_tenant, p_amont_type, p_amont_id, p_amont_ligne,
          p_aval_type, p_aval_id, p_aval_ligne,
          p_link_type, p_effet, COALESCE(p_payload, '{}'::jsonb), auth.uid(), v_tour)
  ON CONFLICT (tenant_id, amont_type, amont_id, effet,
               COALESCE(amont_ligne_id, '00000000-0000-0000-0000-000000000000'::uuid))
    WHERE etat = 'actif'
  DO UPDATE SET payload       = document_links.payload || EXCLUDED.payload,
                link_type     = EXCLUDED.link_type,
                aval_type     = EXCLUDED.aval_type,
                aval_id       = EXCLUDED.aval_id,
                aval_ligne_id = EXCLUDED.aval_ligne_id
  RETURNING id INTO v_id;

  RETURN v_id;
END $fn$;

COMMENT ON FUNCTION public.link_documents(uuid, text, uuid, text, uuid, text, text, jsonb, uuid, uuid) IS
  'L0 + 312 + 451 : déclare un lien amont → aval pour un effet donné, APRÈS avoir vérifié que l''amont, l''aval et leurs lignes existent dans la société (registre chain_document_types). Idempotent (index unique partiel + ON CONFLICT), fusionne le payload au rejeu.';

-- Les droits de la 252 sont conservés par CREATE OR REPLACE ; on les réaffirme.
REVOKE ALL ON FUNCTION public.link_documents(uuid, text, uuid, text, uuid, text, text, jsonb, uuid, uuid) FROM PUBLIC, anon, authenticated;
