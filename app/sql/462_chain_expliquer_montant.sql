-- ═══════════════════════════════════════════════════════════════════════════
-- 462 — I-08 : dérouler la chaîne qui produit un montant
-- ═══════════════════════════════════════════════════════════════════════════
--
-- La 461 a posé le dictionnaire : un indicateur est une requête NOMMÉE et
-- DATÉE, et deux définitions concurrentes sont impossibles. C'est la
-- condition de possibilité d'I-08 ; ce fichier en est l'autre moitié, celle
-- que le client voit : « sur n'importe quel montant, un bouton qui déroule
-- la chaîne des documents et écritures qui produit ce montant, avec les
-- liens vers chaque pièce ».
--
-- CE QUE CE FICHE NE FAIT PAS, ET C'EST L'ESSENTIEL.
--
-- Il ne CALCULE RIEN. Un montant n'est pas recomposé ici : il est LU sur
-- les lignes d'écriture qui le portent réellement. Il n'INVENTE AUCUN
-- lien : il ne connaît que ce que les maillons ont tracé (460). Un chiffre
-- dont aucune chaîne ne le porte est renvoyé VIDE, avec le motif — jamais
-- un chiffre fabriqué, jamais un « probablement dû à ». Un chiffre qu'on
-- ne sait pas expliquer doit le dire : c'est tout le sens d'I-08.
--
-- LES TROIS GENRES RENDUS.
--   'document' : la pièce de la chaîne (la facture, sa commande, son BL) ;
--   'ecriture' : l'écriture comptable produite par ce document ;
--   'ligne'    : la ligne qui porte le montant — le compte, le débit, le
--                crédit. C'est là que le chiffre se retrouve, ligne à ligne.
--
-- `montant` vaut le DÉBIT (jamais le crédit) : une somme de lignes mixtes
-- ne veut rien dire, et l'écran décide comment l'afficher. `debit` indique
-- le sens, pour qu'il puissele total des deux côtés.
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.chain_expliquer_montant(
  p_tenant uuid,
  p_type   text,
  p_id     uuid
)
RETURNS TABLE (
  genre       text,
  type        text,
  id          uuid,
  libelle     text,
  libelle_piece text,
  effet       text,
  lien_etat   text,
  profondeur  integer,
  montant     numeric,
  debit       boolean,
  date_piece  date
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $fn$
DECLARE
  v_courant uuid := current_tenant_id();
BEGIN
  IF p_tenant IS NULL OR p_type IS NULL OR p_id IS NULL THEN
    RAISE EXCEPTION 'Explication : société, type et document sont obligatoires.'
      USING ERRCODE = '23514';
  END IF;
  -- Même garde que la Vue Chaîne (460) : un client ne voit que sa société,
  -- et il doit y appartenir.
  IF auth.uid() IS NOT NULL
     AND (v_courant IS NULL OR p_tenant IS DISTINCT FROM v_courant) THEN
    RAISE EXCEPTION 'Explication : cette société n''est pas la société active.'
      USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  WITH chaine AS (
    -- On réutilise la Vue Chaîne : une seule définition de « la chaîne ».
    SELECT * FROM public.chain_document_arborescence(p_tenant, p_type, p_id, 'aval', 20, true)
  ),
  -- Les pièces comptables que la chaîne contient (écritures produites).
  ecritures AS (
    SELECT DISTINCT c.id, c.profondeur, c.effet, c.etat
      FROM chaine c
     WHERE c.type = 'journal_entries'
  ),
  lignes AS (
    SELECT e.id, e.profondeur, e.effet, e.etat,
           l.id            AS ligne_id,
           l.account_code, l.account_name, l.description,
           coalesce(l.debit, 0) AS debit,
           coalesce(l.credit, 0) AS credit,
           l.line_date
      FROM ecritures e
      JOIN public.journal_lines l ON l.journal_id = e.id AND l.tenant_id = p_tenant
  )
  -- 1. Les DOCUMENTS de la chaîne, le point de départ en tête.
  SELECT 'document'::text, c.type, c.id, c.libelle, NULL::text, c.effet,
         c.etat, c.profondeur, NULL::numeric, NULL::boolean, NULL::date
    FROM chaine c
  UNION ALL
  -- 2. Les ÉCRITURES produites.
  SELECT 'ecriture'::text, 'journal_entries'::text, e.id, je.number, je.description,
         e.effet, e.etat, e.profondeur, coalesce(je.total_debit, 0), true, je.date
    FROM ecritures e
    JOIN public.journal_entries je ON je.id = e.id AND je.tenant_id = p_tenant
  UNION ALL
  -- 3. Les LIGNES : là où le montant se retrouve, compte par compte.
  SELECT 'ligne'::text, 'journal_lines'::text, l.ligne_id,
         l.account_code, l.description, l.effet, l.etat, l.profondeur,
         l.debit, (l.debit <> 0), l.line_date
    FROM lignes l
  ORDER BY 1, 8, 3;
END $fn$;

COMMENT ON FUNCTION public.chain_expliquer_montant(uuid, text, uuid) IS
  '462 (I-08) : le « pourquoi ce chiffre ? ». Déroule, pour un document, les pièces de sa chaîne (460), les ÉCRITURES produites et les LIGNES qui portent le montant. Ne calcule rien et n''invente aucun lien : un chiffre qu''aucune chaîne ne porte est renvoyé vide, jamais fabriqué.';

REVOKE ALL ON FUNCTION public.chain_expliquer_montant(uuid, text, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.chain_expliquer_montant(uuid, text, uuid) TO authenticated, service_role;